import XCTest
import WebKit
@testable import SuJian

@MainActor
final class ReadingPlaceCaptureTests: XCTestCase {
    func testLeavingBeforeDebounceSavesTheLatestScrollPosition() {
        var saved: [ReadingPlace] = []
        let coordinator = MarkdownWebView.Coordinator(
            onAnchorConsumed: {}, onOpenHref: { _ in },
            onReadingPlace: { saved.append($0) }, onChromeVisibility: { _ in }
        )
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 500))
        coordinator.attach(webView)
        coordinator.didFinishFirstLoad = true
        webView.scrollView.contentSize = CGSize(width: 320, height: 2_000)
        webView.scrollView.contentOffset = CGPoint(x: 0, y: 300)
        webView.scrollView.contentOffset = CGPoint(x: 0, y: 650)

        coordinator.flushPlace()
        coordinator.detach()

        XCTAssertEqual(saved.last?.offsetY, 650)
        XCTAssertEqual(saved.last?.contentHeight, 2_000)
        XCTAssertNil(saved.last?.anchor)
    }

    func testLeavingWithoutScrollingDoesNotOverwriteTheSavedPosition() {
        var saved: [ReadingPlace] = []
        let coordinator = MarkdownWebView.Coordinator(
            onAnchorConsumed: {}, onOpenHref: { _ in },
            onReadingPlace: { saved.append($0) }, onChromeVisibility: { _ in }
        )
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 500))
        coordinator.attach(webView)
        coordinator.didFinishFirstLoad = true
        coordinator.flushPlace()
        coordinator.detach()
        XCTAssertTrue(saved.isEmpty)
    }

    func testAnchorJumpToTopSavesTheBeginning() {
        var saved: [ReadingPlace] = []
        let coordinator = MarkdownWebView.Coordinator(
            onAnchorConsumed: {}, onOpenHref: { _ in },
            onReadingPlace: { saved.append($0) }, onChromeVisibility: { _ in }
        )
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 500))
        coordinator.attach(webView)
        coordinator.didFinishFirstLoad = true
        webView.scrollView.contentSize = CGSize(width: 320, height: 2_000)
        webView.scrollView.contentOffset = CGPoint(x: 0, y: 650)

        coordinator.scroll(webView, to: "h1")
        webView.scrollView.contentOffset = .zero
        coordinator.flushPlace()
        coordinator.detach()
        XCTAssertEqual(saved.last?.offsetY, 0)
    }

    func testStatusBarReturnToTopReplacesTheSavedPosition() {
        var saved: [ReadingPlace] = []
        let coordinator = MarkdownWebView.Coordinator(
            onAnchorConsumed: {}, onOpenHref: { _ in },
            onReadingPlace: { saved.append($0) }, onChromeVisibility: { _ in }
        )
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 500))
        coordinator.attach(webView)
        coordinator.didFinishFirstLoad = true
        webView.scrollView.contentSize = CGSize(width: 320, height: 2_000)
        webView.scrollView.contentOffset = CGPoint(x: 0, y: 650)

        webView.scrollView.contentOffset = .zero
        coordinator.flushPlace()
        coordinator.detach()
        XCTAssertEqual(saved.last?.offsetY, 0)
    }

    func testRestorationWaitsForRealWebViewToSettleBeforeAcceptingProgrammaticTop() async throws {
        var saved: [ReadingPlace] = []
        let coordinator = MarkdownWebView.Coordinator(
            onAnchorConsumed: {}, onOpenHref: { _ in },
            onReadingPlace: { saved.append($0) }, onChromeVisibility: { _ in }
        )
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 500))
        let window = UIWindow(frame: webView.frame)
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.addSubview(webView)
        defer {
            coordinator.detach()
            webView.navigationDelegate = nil
            window.isHidden = true
        }
        coordinator.attach(webView)
        coordinator.initialPlace = ReadingPlace(anchor: nil, delta: 0, offsetY: 650, contentHeight: 2000)
        coordinator.noteLoadStarted(anchor: nil)
        webView.navigationDelegate = coordinator
        webView.loadHTMLString("<html><body style='height:2000px'>Content</body></html>", baseURL: nil)

        let deadline = Date().addingTimeInterval(10)
        while !coordinator.isRestoringPlace && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(coordinator.isRestoringPlace)

        webView.scrollView.contentOffset = CGPoint(x: 0, y: 150)
        webView.scrollView.contentOffset = .zero
        XCTAssertTrue(saved.isEmpty)
        try await Task.sleep(nanoseconds: 250_000_000)
        webView.scrollView.contentSize = CGSize(width: 320, height: 2_100)
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertTrue(coordinator.isRestoringPlace, "内容尺寸变化应重新等待布局稳定")
        XCTAssertTrue(saved.isEmpty)

        while coordinator.isRestoringPlace && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(coordinator.isRestoringPlace)

        webView.scrollView.contentOffset = CGPoint(x: 0, y: 600)
        webView.scrollView.contentOffset = .zero
        coordinator.flushPlace()
        XCTAssertEqual(saved.last?.offsetY, 0)
    }
}
