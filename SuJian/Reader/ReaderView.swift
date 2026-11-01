import SwiftUI

struct ReaderView: View {
    let recordID: UUID
    var initialAnchor: String? = nil

    var routeToken: UUID? = nil
    var isWide = false

    var canGoBack = false

    var onBack: () -> Void = {}

    var onToggleLibrary: (() -> Void)? = nil

    var isFrontmost = true
    @Environment(LibraryStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("readingScale") private var readingScale = 1.0
    @State private var document: OpenedDocument?
    @State private var rendered: RenderedMarkdown?
    @State private var failure: String?
    @State private var showOutline = false
    @State private var showTypeSize = false
    @State private var anchor: String?
    @State private var showFormattingCue = false
    @State private var pageVisible = false
    @State private var lineDim = false
    @State private var showsChrome = true
    @State private var hasVerticalBar = false

    @State private var chromeHeight: CGFloat = 48
    @State private var chromeTopExtra: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.readingPlaces) private var readingPlaces
    @Environment(WindowIntents.self) private var intents

    private static let anchorGap: CGFloat = 14

    private var record: ReadingRecord? {
        store.records.first { $0.id == recordID }
    }

    private var scale: Double {
        let extra: Double
        switch dynamicTypeSize {
        case .xSmall: extra = 0.92
        case .small: extra = 0.96
        case .medium, .large: extra = 1
        case .xLarge: extra = 1.08
        case .xxLarge: extra = 1.16
        case .xxxLarge: extra = 1.24
        default:
            extra = dynamicTypeSize.isAccessibilitySize ? 1.4 : 1
        }
        return readingScale * extra
    }

    private var pageHTML: String? {
        guard let rendered else { return nil }
        return ReaderDocument.html(
            rendered: rendered,
            fallbackTitle: record?.title ?? document?.url.deletingPathExtension().lastPathComponent ?? String(localized: "未命名"),
            scale: scale,
            dark: colorScheme == .dark,
            wide: isWide,
            topInset: Double(chromeTopExtra)
        )
    }

    var body: some View {
        ZStack {
            if let failure {
                failureView(failure)
            } else if let pageHTML, let document {
                MarkdownWebView(
                    html: pageHTML,
                    contentKey: rendered?.bodyHTML ?? "",
                    baseURL: DocumentLink.baseDirectory(for: document.url),
                    dark: colorScheme == .dark,
                    scale: scale,
                    anchor: anchor,
                    anchorTopInset: chromeHeight + Self.anchorGap + chromeTopExtra,
                    topInset: chromeTopExtra,
                    revealed: pageVisible,
                    isActive: scenePhase == .active,
                    initialPlace: readingPlaces.place(for: recordID),
                    onReadingPlace: { readingPlaces.save($0, for: recordID) },
                    onAnchorConsumed: {
                        anchor = nil
                        if let routeToken { store.markAnchorConsumed(routeToken) }
                    },
                    onOpenHref: openHref,
                    onChromeVisibility: setChrome
                )
                .ignoresSafeArea(edges: .bottom)
            }
            formattingCue
                .opacity(showFormattingCue && !pageVisible && failure == nil ? 1 : 0)
                .allowsHitTesting(false)
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    PaperChromeFade()
                        .frame(height: chromeHeight + QuietBeauty.chromeFade)
                        .offset(y: chromeShown ? 0 : -28)
                        .opacity(chromeShown ? 1 : 0)
                        .allowsHitTesting(false)
                    readerChrome
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { chromeHeight = $0 }
                        .offset(y: chromeShown ? 0 : -28)
                        .opacity(chromeShown ? 1 : 0)
                        .allowsHitTesting(chromeShown)
                }
                Spacer(minLength: 0)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: pageVisible)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: showFormattingCue)
        .background(Ink.paper.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .background {
            ReaderPopGesture()
        }
        .background {
            VerticalBarPresence(isPresent: $hasVerticalBar)
        }
        .sheet(isPresented: sheetOutline) {
            OutlineSheet(entries: rendered?.outline ?? []) { id in
                anchor = id
                showOutline = false
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Ink.paper)
            .sheetSkipsVerticalBar()
        }
        .onChange(of: intents.outlineTick) { _, _ in
            guard isFrontmost, pageVisible, rendered?.outline.isEmpty == false else { return }
            showTypeSize = false
            showOutline.toggle()
        }
        .task(id: recordID) {
            guard document == nil || rendered == nil else { return }
            await load()
        }
    }

    private var chromeShown: Bool {
        isWide || hasVerticalBar || failure != nil || showsChrome
    }

    private var sheetOutline: Binding<Bool> {
        Binding(
            get: { showOutline && !isWide },
            set: { showOutline = $0 }
        )
    }

    private var popoverOutline: Binding<Bool> {
        Binding(
            get: { showOutline && isWide },
            set: { showOutline = $0 }
        )
    }

    private func circleButton(
        _ symbol: String,
        label: LocalizedStringKey,
        color: Color = Ink.chrome(active: false),
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(color)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(Text(label))
    }

    private var outlineButton: some View {
        Button("目录") {
            showTypeSize = false
            showOutline = true
        }
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(Ink.bronze)
            .frame(height: 44)
            .padding(.horizontal, 16)
            .disabled(!pageVisible || rendered?.outline.isEmpty != false)
            .popover(isPresented: popoverOutline, arrowEdge: .top) {
                OutlineSheet(entries: rendered?.outline ?? [], showsDone: false) { id in
                    anchor = id
                    showOutline = false
                }
                .frame(width: 360, height: 520)
                .presentationCompactAdaptation(.popover)
                .presentationBackground(Ink.paper)
            }
    }

    private var readerChrome: some View {
        HStack(spacing: 12) {
            if isWide {
                if let onToggleLibrary {
                    circleButton("sidebar.leading", label: "文库", action: onToggleLibrary)
                }
                if canGoBack {
                    circleButton("chevron.backward", label: "返回", color: Ink.bronze, action: onBack)
                }
            } else {
                circleButton("chevron.backward", label: "返回", color: Ink.bronze) { dismiss() }
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                outlineButton
                Button {
                    showOutline = false
                    showTypeSize = true
                } label: {
                    Text("Aa")
                        .inkSerif(20, relativeTo: .body)
                        .foregroundStyle(Ink.bronze)
                        .frame(height: 44)
                        .padding(.horizontal, 16)
                }
                .accessibilityLabel(Text("字号"))
                .disabled(!pageVisible)
                .popover(isPresented: $showTypeSize, arrowEdge: .top) {
                    TypeSizePopover(scale: $readingScale)
                        .presentationCompactAdaptation(.popover)
                }
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .padding(.leading, 16)

        .padding(.trailing, hasVerticalBar ? 28 : 16)
        .padding(.top, 4)
        .topChromeInset { chromeTopExtra = $0 }
    }

    private func failureView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            InkRule()
            Text(message)
                .inkSongti(22)
                .foregroundStyle(Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
            Button("从文库移除") {
                store.delete(ids: [recordID])
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Ink.seal)
            .padding(.top, 8)
            Button("返回") { isWide ? onBack() : dismiss() }
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Ink.bronze)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var formattingCue: some View {
        VStack(spacing: 16) {
            InkRule()
                .opacity(reduceMotion || !lineDim ? 1 : 0.35)
            Text("正在排版")
                .inkSongti(16)
                .foregroundStyle(Ink.soft)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: showFormattingCue) { _, visible in
            guard visible, !reduceMotion else { return }
            lineDim = false
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                lineDim = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("正在排版"))
    }

    private func setChrome(_ visible: Bool) {
        guard pageVisible, failure == nil, showsChrome != visible else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) {
            showsChrome = visible
        }
    }

    private func load() async {
        guard let record else {
            failure = String(localized: "文库里已经没有这份记录。")
            return
        }
        let anchorSpent = routeToken.map { store.consumedAnchorTokens.contains($0) } ?? false
        if anchor == nil, !anchorSpent { anchor = initialAnchor }
        showFormattingCue = false
        pageVisible = false
        await Task.yield()
        let cue = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 32_000_000)
            guard !Task.isCancelled, rendered == nil, failure == nil else { return }
            showFormattingCue = true
        }
        defer { cue.cancel() }
        do {
            let access = try store.beginAccess(record)
            let url = access.url
            let parsed: (text: String, rendered: RenderedMarkdown)
            do {
                parsed = try await Self.readAndRender(url)
            } catch {
                access.stop()
                throw error
            }
            if Task.isCancelled {
                access.stop()
                return
            }
            let opened = OpenedDocument(
                url: url,
                text: parsed.text,
                byteCount: access.byteCount,
                startedAccess: access.started
            )
            document?.close()
            document = opened
            rendered = parsed.rendered
            failure = nil
            store.noteReading(id: record.id, title: parsed.rendered.h1Text, byteCount: access.byteCount)
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) {
                pageVisible = true
            }
        } catch {
            failure = String(localized: "无法读取这份文稿。它可能已被移动或删除。")
        }
    }

    private static func readAndRender(_ url: URL) async throws -> (text: String, rendered: RenderedMarkdown) {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let text = try TextFile.read(from: url)
                    continuation.resume(returning: (text, MarkdownRender.render(text)))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func openHref(_ href: String) {
        guard let current = document?.url else { return }
        switch DocumentLink.resolve(href, from: current) {
        case .scroll(let fragment):
            anchor = fragment
        case .external(let url):
            UIApplication.shared.open(url)
        case .open(let file, let fragment):
            guard let id = store.adoptFile(at: file) else { return }
            if id == recordID {
                if let fragment { anchor = fragment }
                return
            }

            Task { @MainActor in
                store.present(id, anchor: fragment)
            }
        case .ignore:
            break
        }
    }
}

private struct ReaderPopGesture: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.enable()
    }

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            enable()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            guard let pop = navigationController?.interactivePopGestureRecognizer else { return }
            if pop.delegate === self {
                pop.delegate = nil
            }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            enable()
        }

        func enable() {
            guard let pop = navigationController?.interactivePopGestureRecognizer else { return }
            pop.isEnabled = true
            pop.delegate = self
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}

private struct PaperChromeFade: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Ink.paper, location: 0),
                .init(color: Ink.paper, location: 0.58),
                .init(color: Ink.paper.opacity(0), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct TypeSizePopover: View {
    @Binding var scale: Double
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    private var current: Double {
        ReadingScale.options.min { abs($0.value - scale) < abs($1.value - scale) }?.value ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(ReadingScale.options.enumerated()), id: \.element.id) { index, option in
                let chosen = abs(option.value - current) < 0.001
                Button {
                    scale = option.value
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Ink.bronze)
                            .opacity(chosen ? 1 : 0)
                            .frame(width: 14, height: 14)
                        Text(LocalizedStringKey(option.name))
                            .inkSerif(17)
                            .foregroundStyle(chosen ? Ink.bronze : Ink.primary)
                    }
                    .padding(.horizontal, 16)
                    .frame(width: Self.menuWidth, height: 44, alignment: .leading)
                    .contentShape(Rectangle())
                    .overlay(alignment: .bottom) {
                        if index < ReadingScale.options.count - 1 {
                            Rectangle()
                                .fill(Ink.hairline)
                                .frame(height: 1 / max(displayScale, 1))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(LocalizedStringKey(option.name)))
                .accessibilityAddTraits(chosen ? .isSelected : AccessibilityTraits())
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 14)
        .fixedSize(horizontal: true, vertical: true)
    }

    private static let menuWidth: CGFloat = 148
}

private struct OutlineRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }
}

private struct OutlineSheet: View {
    let entries: [OutlineEntry]
    var showsDone = true
    var select: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(entries) { entry in
                        Button {
                            select(entry.id)
                        } label: {
                            Text(entry.text)
                                .inkSongti(entry.level == 1 ? QuietBeauty.listTitleSize : QuietBeauty.proseSize)
                                .foregroundStyle(Ink.primary)
                                .multilineTextAlignment(.leading)
                                .padding(.leading, CGFloat(entry.level - 1) * 16)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(Ink.hairline).frame(height: QuietBeauty.hairlineWidth)
                                }
                        }
                        .buttonStyle(OutlineRowButtonStyle())
                    }
                }
                .padding(.horizontal, QuietBeauty.pageInset)
                .padding(.top, 8)
            }
            .background(Ink.paper)
            .navigationTitle("目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsDone {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }
                    }
                }
            }
        }
        .tint(Ink.bronze)
    }
}
