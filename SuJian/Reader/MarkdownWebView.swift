import SwiftUI
import UIKit
import WebKit

struct MarkdownWebView: UIViewRepresentable {
    var html: String

    var contentKey: String
    var baseURL: URL?
    var dark: Bool
    var scale: Double
    var anchor: String?

    var anchorTopInset: CGFloat = 12
    var topInset: CGFloat = 0
    var revealed: Bool

    var isActive: Bool
    var initialPlace: ReadingPlace?
    var onReadingPlace: (ReadingPlace) -> Void
    var onAnchorConsumed: () -> Void
    var onOpenHref: (String) -> Void
    var onChromeVisibility: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onAnchorConsumed: onAnchorConsumed,
            onOpenHref: onOpenHref,
            onReadingPlace: onReadingPlace,
            onChromeVisibility: onChromeVisibility
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(
            source: Coordinator.clickScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        controller.add(context.coordinator, name: Coordinator.linkHandler)
        configuration.userContentController = controller
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear

        view.underPageBackgroundColor = QuietBeauty.paper.uiColor

        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.allowsBackForwardNavigationGestures = false
        view.alpha = 0
        #if DEBUG
        view.isInspectable = true
        #endif
        context.coordinator.attach(view)
        return view
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.flushPlace()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.linkHandler)
        coordinator.detach()
        webView.navigationDelegate = nil
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onAnchorConsumed = onAnchorConsumed
        coordinator.onOpenHref = onOpenHref
        coordinator.onReadingPlace = onReadingPlace
        coordinator.onChromeVisibility = onChromeVisibility
        coordinator.initialPlace = initialPlace
        coordinator.anchorTopInset = anchorTopInset
        coordinator.topInset = topInset
        coordinator.revealed = revealed
        if !isActive { coordinator.flushPlace() }
        let scrollView = webView.scrollView
        scrollView.contentInsetAdjustmentBehavior = .never
        webView.underPageBackgroundColor = QuietBeauty.paper.uiColor

        scrollView.indicatorStyle = dark ? .default : .black

        let viewChanged = coordinator.loadedWebView !== webView
        if viewChanged {
            coordinator.loadedWebView = webView
            coordinator.prepareForNewPage()
        }

        if coordinator.loadedContent != contentKey || coordinator.loadedBase != baseURL {
            coordinator.loadedContent = contentKey
            coordinator.loadedBase = baseURL
            coordinator.loadedDark = dark
            coordinator.loadedScale = scale
            coordinator.noteLoadStarted(anchor: anchor)
            webView.loadHTMLString(html, baseURL: baseURL)
            return
        }

        if coordinator.loadedDark != dark || abs((coordinator.loadedScale ?? scale) - scale) > 0.001 {
            coordinator.loadedDark = dark
            coordinator.loadedScale = scale
            coordinator.applyAppearance(to: webView, dark: dark, scale: scale)
        }
        if coordinator.didFinishFirstLoad, coordinator.loadedTopInset != topInset {
            coordinator.applyTopInset(to: webView)
        }

        if !coordinator.didFinishFirstLoad {
            if anchor != nil { coordinator.pendingAnchor = anchor }
        } else if let anchor, anchor != coordinator.lastScrolledAnchor {
            coordinator.lastScrolledAnchor = anchor
            coordinator.pendingAnchor = nil
            coordinator.scroll(webView, to: anchor)

            DispatchQueue.main.async { coordinator.onAnchorConsumed() }
        } else if anchor == nil {
            coordinator.lastScrolledAnchor = nil
        }
        if revealed, !webView.isLoading, !coordinator.didReveal {
            coordinator.reveal(webView)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onAnchorConsumed: () -> Void
        var onOpenHref: (String) -> Void
        weak var loadedWebView: WKWebView?
        var loadedContent: String?
        var loadedBase: URL?
        var loadedDark: Bool?
        var loadedScale: Double?
        var topInset: CGFloat = 0
        var loadedTopInset: CGFloat?
        var pendingAnchor: String?
        var revealed = false
        var initialPlace: ReadingPlace?
        var anchorTopInset: CGFloat = 12
        var onReadingPlace: (ReadingPlace) -> Void
        var onChromeVisibility: (Bool) -> Void
        private var fadingIn = false
        var didReveal = false
        var didFinishFirstLoad = false
        private var handledNavigation = false
        var lastScrolledAnchor: String?
        private var placeCapture: DispatchWorkItem?
        // Invalidate earlier JavaScript captures so late results cannot overwrite newer positions.
        private var placeGeneration = 0
        private var placeIsPending = false

        private var anchorJumpMayReachTop = false
        private var anchorJumpGeneration = 0

        private var lastObservedOffsetY: CGFloat = 0
        private var offsetObservation: NSKeyValueObservation?
        private var sizeObservation: NSKeyValueObservation?

        private(set) var isRestoringPlace = false
        private var restoreScriptFinished = false
        private var restoreGeneration = 0
        private var navigationGeneration = 0
        private var restoreSettling: DispatchWorkItem?
        private weak var webView: WKWebView?
        private var chromeY: CGFloat = 0
        private var chromeDrift: CGFloat = 0

        private var lastHref: String?
        private var lastHrefAt = Date.distantPast

        init(
            onAnchorConsumed: @escaping () -> Void,
            onOpenHref: @escaping (String) -> Void,
            onReadingPlace: @escaping (ReadingPlace) -> Void,
            onChromeVisibility: @escaping (Bool) -> Void
        ) {
            self.onAnchorConsumed = onAnchorConsumed
            self.onOpenHref = onOpenHref
            self.onReadingPlace = onReadingPlace
            self.onChromeVisibility = onChromeVisibility
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Self.linkHandler, let href = message.body as? String else { return }
            let now = Date()
            if href == lastHref, now.timeIntervalSince(lastHrefAt) < 0.35 { return }
            lastHref = href
            lastHrefAt = now
            let open = onOpenHref
            if Thread.isMainThread {
                open(href)
            } else {
                DispatchQueue.main.async { open(href) }
            }
        }

        func attach(_ webView: WKWebView) {
            self.webView = webView
            offsetObservation = webView.scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
                self?.schedulePlaceCapture()
                self?.reportChrome(scrollView)
            }
            sizeObservation = webView.scrollView.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
                self?.settleRestoredPlace()
            }
        }

        func detach() {
            placeCapture?.cancel()
            endRestoringPlace()
            navigationGeneration += 1
            offsetObservation?.invalidate()
            offsetObservation = nil
            sizeObservation?.invalidate()
            sizeObservation = nil
            loadedWebView = nil
            webView = nil
        }

        func prepareForNewPage() {
            loadedContent = nil
            loadedBase = nil
            noteLoadStarted(anchor: nil)
            didReveal = false
        }

        func noteLoadStarted(anchor: String?) {
            navigationGeneration += 1
            pendingAnchor = anchor
            lastScrolledAnchor = nil
            didFinishFirstLoad = false
            loadedTopInset = nil
            handledNavigation = false
            placeCapture?.cancel()
            placeCapture = nil
            placeGeneration += 1
            placeIsPending = false
            anchorJumpGeneration += 1
            anchorJumpMayReachTop = false
            lastObservedOffsetY = 0
            endRestoringPlace()
        }

        func flushPlace() {
            // On teardown, save an approximate position if asynchronous capture is still pending.

            placeCapture?.cancel()
            placeGeneration += 1
            guard placeIsPending, didFinishFirstLoad, let scrollView = webView?.scrollView else { return }
            placeIsPending = false
            let y = max(0, Double(scrollView.contentOffset.y))
            let place = ReadingPlace(
                anchor: nil,
                delta: 0,
                offsetY: y <= 24 ? 0 : y,
                contentHeight: Double(scrollView.contentSize.height)
            )
            onReadingPlace(place)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let firstFinish = !handledNavigation
            handledNavigation = true
            guard firstFinish else {
                pendingAnchor = nil
                return
            }
            applyTopInset(to: webView)
            if let anchor = pendingAnchor {
                pendingAnchor = nil
                lastScrolledAnchor = anchor
                didFinishFirstLoad = true
                scroll(webView, to: anchor)
                onAnchorConsumed()
                if revealed { reveal(webView) }
                return
            }
            if let place = initialPlace {
                isRestoringPlace = true
                restoreScriptFinished = false
                restoreGeneration += 1
                let generation = restoreGeneration
                let navigation = navigationGeneration
                didFinishFirstLoad = true
                restore(place, in: webView) { [weak self] in
                    guard let self, self.navigationGeneration == navigation else { return }
                    if self.restoreGeneration == generation {
                        self.restoreScriptFinished = true
                        self.settleRestoredPlace()
                    }
                    if self.revealed { self.reveal(webView) }
                }
                return
            }
            didFinishFirstLoad = true
            if revealed { reveal(webView) }
        }

        func applyTopInset(to webView: WKWebView) {
            loadedTopInset = topInset
            webView.evaluateJavaScript(
                """
                (function() {
                  var root = document.documentElement;
                  var oldInset = parseFloat(root.style.getPropertyValue('--chrome-top-extra')) || 0;
                  var newInset = \(String(format: "%.1f", Double(topInset)));
                  var y = window.pageYOffset || 0;
                  root.style.setProperty('--chrome-top-extra', newInset + 'px');
                  if (y > 24) window.scrollTo(0, Math.max(0, y + newInset - oldInset));
                })()
                """
            )
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated else {
                decisionHandler(.allow)
                return
            }

            decisionHandler(.cancel)
        }

        func reveal(_ webView: WKWebView) {
            guard revealed else {
                fadingIn = false
                webView.layer.removeAllAnimations()
                webView.alpha = 0
                return
            }
            if UIAccessibility.isReduceMotionEnabled {
                didReveal = true
                webView.alpha = 1
                return
            }
            guard webView.alpha < 1, !fadingIn else { return }
            fadingIn = true
            didReveal = true
            UIView.animate(
                withDuration: 0.45,
                delay: 0,
                options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState]
            ) {
                webView.alpha = 1
            } completion: { [weak self] _ in
                self?.fadingIn = false
            }
        }

        func applyAppearance(to webView: WKWebView, dark: Bool, scale: Double) {
            let theme = dark ? "ink" : "paper"
            let scaleText = String(format: "%.3f", scale)
            let y = webView.scrollView.contentOffset.y
            webView.evaluateJavaScript(
                """
                (function() {
                  var y = window.pageYOffset || 0;
                  document.documentElement.className = '\(theme)';
                  document.documentElement.style.setProperty('--scale', '\(scaleText)');
                  window.scrollTo(0, y);
                  requestAnimationFrame(function() { window.scrollTo(0, y); });
                })()
                """
            )
            let scrollView = webView.scrollView
            DispatchQueue.main.async {
                guard abs(scrollView.contentOffset.y - y) >= 1 else { return }
                scrollView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
            }
        }

        private func reportChrome(_ scrollView: UIScrollView) {
            let y = scrollView.contentOffset.y
            if y <= 12 {
                chromeDrift = 0
                chromeY = y
                onChromeVisibility(true)
                return
            }
            let delta = y - chromeY
            chromeY = y
            let user = scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
            guard user, abs(delta) < 240 else { return }
            chromeDrift = delta > 0 ? max(0, chromeDrift) + delta : min(0, chromeDrift) + delta
            if chromeDrift > 36 {
                chromeDrift = 0
                onChromeVisibility(false)
            } else if chromeDrift < -18 {
                chromeDrift = 0
                onChromeVisibility(true)
            }
        }

        private func schedulePlaceCapture() {
            guard didFinishFirstLoad, let scrollView = webView?.scrollView else { return }
            let offsetY = scrollView.contentOffset.y
            if isRestoringPlace {
                let user = scrollView.isTracking || scrollView.isDragging
                if user {
                    endRestoringPlace()
                } else {
                    lastObservedOffsetY = offsetY
                    settleRestoredPlace()
                    return
                }
            }
            let cameFromBelow = lastObservedOffsetY > 24 && offsetY <= 24
            lastObservedOffsetY = offsetY
            placeGeneration += 1
            placeCapture?.cancel()
            if offsetY <= 24 {
                let user = scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating

                guard user || anchorJumpMayReachTop || cameFromBelow else {
                    placeIsPending = false
                    return
                }
                anchorJumpMayReachTop = false
                placeIsPending = false
                let place = ReadingPlace(
                    anchor: nil,
                    delta: 0,
                    offsetY: 0,
                    contentHeight: Double(scrollView.contentSize.height)
                )
                onReadingPlace(place)
                return
            }
            placeIsPending = true
            let generation = placeGeneration
            let work = DispatchWorkItem { [weak self] in
                self?.snapshotPlace(generation: generation)
            }
            placeCapture = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }

        // Wait for scroll and content height to stabilize; script completion does not mean layout is finished.
        private func settleRestoredPlace() {
            guard isRestoringPlace, restoreScriptFinished else { return }
            restoreSettling?.cancel()
            let generation = restoreGeneration
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.restoreGeneration == generation else { return }
                self.endRestoringPlace()
            }
            restoreSettling = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }

        private func endRestoringPlace() {
            restoreSettling?.cancel()
            restoreSettling = nil
            restoreGeneration += 1
            restoreScriptFinished = false
            isRestoringPlace = false
        }

        private func snapshotPlace(generation: Int) {
            guard didFinishFirstLoad, let webView else { return }
            webView.evaluateJavaScript(Self.placeScript) { [weak self] value, _ in
                guard let self, self.didFinishFirstLoad, self.placeGeneration == generation,
                      let place = ReadingPlace.parse(value) else { return }
                self.placeIsPending = false
                self.onReadingPlace(place)
            }
        }

        private func restore(_ place: ReadingPlace, in webView: WKWebView, done: @escaping () -> Void) {
            webView.evaluateJavaScript(Self.restoreScript(place)) { _, _ in
                done()
            }
        }

        private static let placeScript = """
        (function() {
          var y = window.pageYOffset || 0;
          var nodes = document.querySelectorAll('h1[id],h2[id],h3[id],h4[id],h5[id],h6[id]');
          var best = null;
          var bestTop = 0;
          for (var i = 0; i < nodes.length; i++) {
            var top = nodes[i].getBoundingClientRect().top + y;
            if (top <= y + 8) { best = nodes[i]; bestTop = top; }
            else break;
          }
          return {
            y: y,
            height: document.documentElement.scrollHeight || 0,
            anchor: best ? best.id : '',
            delta: best ? (y - bestTop) : 0
          };
        })()
        """

        private static func restoreScript(_ place: ReadingPlace) -> String {
            let anchor = place.anchor ?? ""
            let safe = anchor.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) ? anchor : ""
            return """
            (function() {
              var anchor = '\(safe)';
              var el = anchor ? document.getElementById(anchor) : null;
              var y = \(String(format: "%.2f", place.offsetY));
              if (el) {
                var top = el.getBoundingClientRect().top + (window.pageYOffset || 0);
                y = Math.max(0, top + \(String(format: "%.2f", place.delta)));
              } else if (\(String(format: "%.2f", place.contentHeight)) > 1) {
                var height = document.documentElement.scrollHeight || 0;
                y = height * (\(String(format: "%.2f", place.offsetY)) / \(String(format: "%.2f", place.contentHeight)));
              }
              window.scrollTo(0, Math.max(0, y));
            })()
            """
        }

        static let linkHandler = "sujianLink"

        static let clickScript = """
        (function() {
          if (window.__sujianLinks) return;
          window.__sujianLinks = true;
          document.addEventListener('click', function(event) {
            var node = event.target;
            while (node && node.nodeName !== 'A') node = node.parentNode;
            if (!node || !node.getAttribute) return;
            var href = node.getAttribute('href');
            if (!href) return;
            event.preventDefault();
            var handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.sujianLink;
            if (handler) handler.postMessage(href);
          }, true);
        })();
        """

        func scroll(_ webView: WKWebView, to anchor: String) {
            guard anchor.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { return }
            endRestoringPlace()
            anchorJumpGeneration += 1
            let generation = anchorJumpGeneration
            anchorJumpMayReachTop = true
            webView.evaluateJavaScript(
                """
                (function() {
                  var el = document.getElementById('\(anchor)');
                  if (!el) return false;
                  var y = el.getBoundingClientRect().top + (window.pageYOffset || 0) - \(String(format: "%.1f", Double(anchorTopInset)));
                  window.scrollTo({top: Math.max(0, y), left: 0, behavior: 'smooth'});
                  return y <= 24;
                })()
                """
            ) { [weak self, weak webView] value, _ in
                guard let self, self.anchorJumpGeneration == generation else { return }
                if (value as? Bool) != true {
                    self.anchorJumpMayReachTop = false
                } else if let webView, webView.scrollView.contentOffset.y <= 24 {
                    self.schedulePlaceCapture()
                }
            }
        }
    }
}
