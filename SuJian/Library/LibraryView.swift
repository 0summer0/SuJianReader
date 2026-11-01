import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @Environment(WindowIntents.self) private var intents
    @State private var sidebarShown = true
    @State private var windowWidth: CGFloat = 0
    @FocusState private var searchFocused: Bool
    @State private var hasVerticalBar = false
    @State private var importing = false
    @State private var query = ""
    @State private var expandedFolders: Set<String> = []
    @State private var isSelecting = false
    @State private var selection = Set<UUID>()
    @State private var pendingDelete = Set<UUID>()
    @State private var selectionDelete = DialogGate()

    private var keyword: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !keyword.isEmpty
    }

    private var searchHits: [ReadingRecord] {
        store.sortedRecords.filter { LibraryCatalog.matches($0, keyword: keyword) }
    }

    private var sharedRoot: LibraryFolder {
        LibraryCatalog.outline(from: store.records)
    }

    private var recentRecords: [ReadingRecord] {
        LibraryCatalog.recent(from: store.records)
    }

    private var showsShared: Bool {
        !sharedRoot.folders.isEmpty || !sharedRoot.files.isEmpty
    }

    private var outlineRows: [LibraryOutlineRow] {
        LibraryCatalog.rows(in: sharedRoot, expanded: expandedFolders)
    }

    private var listedIDs: Set<UUID> {
        if isSearching { return Set(searchHits.map(\.id)) }
        var ids = Set(recentRecords.map(\.id))
        for row in outlineRows {
            if case .file(let record, _) = row.kind {
                ids.insert(record.id)
            }
        }
        return ids
    }

    private var libraryIDs: Set<UUID> {
        Set(store.records.map(\.id))
    }

    private var selectionBinding: Binding<Set<UUID>> {
        Binding(
            get: { selection },
            set: { proposed in
                selection = LibraryCatalog.keepingCollapsedSelection(
                    current: selection,
                    proposed: proposed,
                    records: store.records,
                    expanded: expandedFolders
                )
            }
        )
    }

    private var showsSystemSearch: Bool {
        !store.records.isEmpty && !isSelecting
    }

    private var keepsSearchController: Bool {
        !store.records.isEmpty
    }

    private var listedFullySelected: Bool {
        !listedIDs.isEmpty && listedIDs.isSubset(of: selection)
    }

    private var showsBothGroups: Bool {
        !isSearching && showsShared && !recentRecords.isEmpty
    }

    private var mastheadCaption: String {
        if isSelecting {
            return selection.isEmpty
                ? String(localized: "选择要删除的记录")
                : String(localized: "已选 \(selection.count)")
        }
        if showsShared && recentRecords.isEmpty { return String(localized: "文稿") }
        return String(localized: "最近阅读")
    }

    private var showsFixedMasthead: Bool {
        if isSelecting { return true }
        if isSearching { return false }
        return !showsBothGroups
    }

    private var editModeBinding: Binding<EditMode> {
        Binding(
            get: { isSelecting ? .active : .inactive },
            set: { _ in
            }
        )
    }

    private static let sideBySideWidth: CGFloat = 900

    private var isWide: Bool {
        horizontalSizeClass == .regular
    }

    private var sidebarPushes: Bool {
        windowWidth >= Self.sideBySideWidth
    }

    private func sidebarWidth(in width: CGFloat) -> CGFloat {
        min(380, max(300, width * 0.34))
    }

    var body: some View {
        shell
            .tint(Ink.bronze)
            .fileImporter(
                isPresented: $importing,
                allowedContentTypes: MarkdownFile.contentTypes,
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    store.importURLs(urls, openSingle: true)
                case .failure:
                    store.errorMessage = String(localized: "没能打开文稿。")
                }
            }
            .alert("无法打开", isPresented: errorPresented) {
                Button("好", role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
            .onAppear {
                store.syncSharedDocuments()
                if let id = store.consumeFocus() { show(id) }
            }
            .onChange(of: store.focusID) { _, _ in
                if let id = store.consumeFocus() { show(id) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.syncSharedDocuments() }
            }
            .onChange(of: libraryIDs) { _, alive in
                selection.formIntersection(alive)
            }
            .onChange(of: store.readerPath.isEmpty) { _, empty in

                if empty { sidebarShown = true }
            }
            .onChange(of: intents.openFileTick) { _, _ in importing = true }
            .onChange(of: intents.libraryTick) { _, _ in toggleLibrary() }
            .onChange(of: intents.searchTick) { _, _ in focusSearch() }
            .onChange(of: intents.backTick) { _, _ in goBack() }
            .background { shortcutKeys }
            .onDrop(of: [UTType.fileURL], isTargeted: nil, perform: acceptDrop)
            .background { MacPaperTitlebar() }
            .refreshable {
                store.syncSharedDocuments()
            }
    }

    @ViewBuilder
    private var shell: some View {
        if isWide, !store.records.isEmpty {
            wideShell
        } else {
            compactShell
        }
    }

    private var compactShell: some View {
        @Bindable var store = store
        return NavigationStack(path: $store.readerPath) {
            libraryScreen(systemSearch: true)
                .navigationDestination(for: ReaderRoute.self) { route in
                    ReaderView(
                        recordID: route.id,
                        initialAnchor: route.anchor,
                        routeToken: route.token,
                        isFrontmost: store.readerPath.last == route
                    )
                    .id(route.token)
                }
        }
    }

    private var wideShell: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let sideWidth = sidebarWidth(in: width)
            let pushes = width >= Self.sideBySideWidth
            ZStack(alignment: .leading) {
                detailColumn
                    .padding(.leading, pushes && sidebarShown ? sideWidth : 0)
                if !pushes && sidebarShown {
                    QuietBeauty.veil.color
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { setSidebar(false) }
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
                if sidebarShown {
                    NavigationStack {
                        libraryScreen(systemSearch: false)
                    }
                    .frame(width: sideWidth)
                    .background(Ink.paper.ignoresSafeArea())
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(QuietBeauty.columnRule.color)
                            .frame(width: 1 / max(displayScale, 1))
                            .ignoresSafeArea()
                    }
                    .shadow(color: QuietBeauty.shadow.color, radius: pushes ? 0 : 18, x: 4, y: 0)
                    .transition(.move(edge: .leading))
                    .zIndex(1)
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: sidebarShown)
            .onChange(of: width, initial: true) { old, new in
                let first = windowWidth == 0
                windowWidth = new

                let pushing = new >= Self.sideBySideWidth
                if first || (old >= Self.sideBySideWidth) != pushing {
                    sidebarShown = pushing || store.readerPath.isEmpty
                }
            }
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        Group {
            if let route = store.readerPath.last {
                ReaderView(
                    recordID: route.id,
                    initialAnchor: route.anchor,
                    routeToken: route.token,
                    isWide: true,
                    canGoBack: store.readerPath.count > 1,
                    onBack: popReader,
                    onToggleLibrary: toggleLibrary
                )
                .id(route.token)
            } else {
                ReaderPlaceholder(showsSidebarButton: !sidebarShown, onToggleLibrary: toggleLibrary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.paper.ignoresSafeArea())
    }

    private func libraryScreen(systemSearch: Bool) -> some View {
        VStack(spacing: 0) {
            libraryChrome
            if store.records.isEmpty {
                emptyLibrary
            } else if isSearching && searchHits.isEmpty {
                missingSearch
            } else {
                if showsFixedMasthead { masthead }
                recordList
            }
            if !systemSearch, showsSystemSearch {
                searchField
            }
        }
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.paper.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .toolbar { toolbar(systemSearch: systemSearch) }
        .modifier(LibrarySearch(enabled: keepsSearchController && systemSearch, query: $query, focus: $searchFocused))
        .background {
            SearchChrome()
        }
        .environment(\.editMode, editModeBinding)
        .background { VerticalBarPresence(isPresent: $hasVerticalBar) }
    }

    private var shortcutKeys: some View {
        Group {
            Button("打开") { importing = true }
                .keyboardShortcut("o", modifiers: .command)
            Button("搜索文稿") { focusSearch() }
                .keyboardShortcut("f", modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func setSidebar(_ shown: Bool) {
        sidebarShown = shown
    }

    private func toggleLibrary() {
        guard isWide, !store.records.isEmpty else { return }
        sidebarShown.toggle()
    }

    private func focusSearch() {
        guard keepsSearchController, !isSelecting else { return }
        if isWide { sidebarShown = true }
        searchFocused = true
    }

    private func popReader() {
        if store.readerPath.count > 1 {
            store.readerPath.removeLast()
        } else {
            store.readerPath = []
        }
    }

    private func goBack() {
        guard !store.readerPath.isEmpty else { return }
        if isWide, store.readerPath.count <= 1 { return }
        store.readerPath.removeLast()
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        let identifier = UTType.fileURL.identifier
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(identifier) {
            accepted = true
            provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                guard let url else { return }
                Task { @MainActor in
                    store.importURLs([url], openSingle: true)
                }
            }
        }
        return accepted
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.clearError() } }
        )
    }

    private func deleteMessage(for ids: Set<UUID>) -> String {
        let chosen = store.records.filter { ids.contains($0.id) }
        let copies = chosen.filter { $0.origin == .importedCopy }.count
        if copies > 0 {
            return String(localized: "移除 \(chosen.count) 条打开记录。分享时复制进素笺的 \(copies) 份副本会一起删除，其余原稿仍留在「文件」里。")
        }
        return String(localized: "移除 \(chosen.count) 条打开记录。原稿仍留在「文件」里。")
    }

    private var libraryChrome: some View {
        HStack(spacing: 12) {
            Text("素笺")
                .inkWordmark()
                .foregroundStyle(Ink.primary)
                .fixedSize()
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                Button {
                    setSelecting(!isSelecting)
                } label: {
                    Text(isSelecting ? "完成" : "选择")
                }
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Ink.bronze)
                .frame(height: 44)
                .padding(.horizontal, 16)
                .disabled(!isSelecting && store.records.isEmpty)
                if !isSelecting {
                    Button("打开") { importing = true }
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Ink.bronze)
                        .frame(height: 44)
                        .padding(.horizontal, 16)
                }
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .padding(.leading, QuietBeauty.pageInset)
        .padding(.trailing, hasVerticalBar ? 28 : 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .topChromeInset()
    }

    @ToolbarContentBuilder
    private func toolbar(systemSearch: Bool) -> some ToolbarContent {
        if showsSystemSearch, systemSearch {
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
        }
        if isSelecting {
            ToolbarItem(placement: .bottomBar) {
                Button {
                    if listedFullySelected {
                        selection.subtract(listedIDs)
                    } else {
                        selection.formUnion(listedIDs)
                    }
                } label: {
                    Text(listedFullySelected ? "取消全选" : "全选")
                }
                .disabled(listedIDs.isEmpty)
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Button {
                    pendingDelete = selection
                    selectionDelete.present()
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel(Text("删除"))
                .disabled(selection.isEmpty)
                .modifier(DeletionDialog(
                    gate: selectionDelete,
                    count: pendingDelete.count,
                    message: deleteMessage(for: pendingDelete),
                    confirm: { performDelete(pendingDelete) }
                ))
            }
        }
    }

    private func show(_ id: UUID, anchor: String? = nil) {
        if isWide, !store.records.isEmpty {
            store.openRoot(id, anchor: anchor)
            if !sidebarPushes { sidebarShown = false }
        } else {
            store.present(id, anchor: anchor)
        }
    }

    private func performDelete(_ ids: Set<UUID>) {
        pendingDelete = []
        let leaving = isSelecting && selection.subtracting(ids).isEmpty
        store.delete(ids: ids)
        if leaving {
            setSelecting(false)
        } else {
            selection.subtract(ids)
        }
    }

    private func setSelecting(_ selecting: Bool) {
        let animation: Animation? = reduceMotion ? nil : .smooth(duration: 0.42)

        if !selecting, animation != nil {
            withAnimation(animation) {
                isSelecting = false
            } completion: {
                guard !isSelecting else { return }
                selection.removeAll()
            }
            return
        }
        withAnimation(animation) {
            isSelecting = selecting
        }
        if !selecting {
            DispatchQueue.main.async {
                guard !isSelecting else { return }
                selection.removeAll()
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Ink.soft)
            TextField("搜索文稿", text: $query)
                .focused($searchFocused)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(Ink.primary)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Ink.soft)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("清除"))
            }
        }
        .font(.system(size: 16))
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(QuietBeauty.field.color, in: Capsule())
        .overlay {
            Capsule().strokeBorder(QuietBeauty.columnRule.color, lineWidth: 1 / max(displayScale, 1))
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 10) {
            InkRule()
            Text(mastheadCaption)
                .font(.system(size: QuietBeauty.metaSize))
                .tracking(isSelecting ? 0 : QuietBeauty.metaSize * QuietBeauty.metaTracking)
                .foregroundStyle(Ink.soft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, QuietBeauty.pageInset)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private var recordList: some View {
        List(selection: selectionBinding) {
            if isSearching {
                ForEach(searchHits) { record in
                    fileRow(record, depth: 0, subtitle: searchSubtitle(record), aligns: false)
                }
            } else {
                if showsShared {
                    if showsBothGroups { captionRow(String(localized: "文稿"), top: 18) }
                    ForEach(outlineRows) { item in
                        outlineRow(item)
                    }
                }
                if !recentRecords.isEmpty {
                    if showsBothGroups { captionRow(String(localized: "最近阅读"), top: showsShared ? 28 : 18) }
                    ForEach(recentRecords) { record in
                        fileRow(record, depth: 0, subtitle: record.subtitle, aligns: false)
                    }
                }
            }
        }
        .listStyle(.plain)
        .tint(QuietBeauty.check.color)
        .scrollContentBackground(.hidden)
        .listSectionSeparator(.hidden)
        .environment(\.defaultMinListRowHeight, 64)
    }

    private func captionRow(_ title: String, top: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            InkRule()
            Text(title)
                .inkSectionLabel()
                .foregroundStyle(Ink.soft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, top)
        .padding(.bottom, 4)
        .accessibilityAddTraits(.isHeader)
        .selectionDisabled()
        .listRowInsets(EdgeInsets(top: 0, leading: QuietBeauty.pageInset, bottom: 0, trailing: QuietBeauty.pageInset))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func outlineRow(_ item: LibraryOutlineRow) -> some View {
        switch item.kind {
        case .folder(let folder):
            folderRow(folder, depth: item.depth)
        case .file(let record, let aligns):
            fileRow(record, depth: item.depth, subtitle: record.subtitle, aligns: aligns)
        }
    }

    private func folderRow(_ folder: LibraryFolder, depth: Int) -> some View {
        let open = expandedFolders.contains(folder.path)
        return Button {
            toggleFolder(folder.path)
        } label: {
            LibraryRow(
                title: folder.name,
                subtitle: String(localized: "\(folder.documentCount) 篇"),
                showsChevron: true,
                chevronOpen: open
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library-folder")
        .accessibilityHint(Text("文件夹"))
        .accessibilityValue(Text(open ? "已展开" : "已折叠"))
        .selectionDisabled()
        .listRowInsets(rowInset(depth: depth, aligns: false))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func fileRow(_ record: ReadingRecord, depth: Int, subtitle: String, aligns: Bool) -> some View {
        Button {
            if isSelecting {
                if selection.contains(record.id) {
                    selection.remove(record.id)
                } else {
                    selection.insert(record.id)
                }
            } else {
                show(record.id)
            }
        } label: {
            LibraryRow(title: record.title, subtitle: subtitle)
        }
        .buttonStyle(.plain)
        .tag(record.id)
        .accessibilityIdentifier("library-file")
        .listRowInsets(rowInset(depth: depth, aligns: aligns))
        .listRowBackground(rowBackground(record.id))
        .listRowSeparator(.hidden)
        .modifier(RowDeletionDialog(
            message: deleteMessage(for: [record.id]),
            confirm: { performDelete([record.id]) }
        ))
    }

    private func rowBackground(_ id: UUID) -> Color {
        if isWide, !isSelecting, store.readerPath.last?.id == id {
            let wash = colorScheme == .dark ? QuietBeauty.selectionWashDark : QuietBeauty.selectionWashLight
            return Ink.bronze.opacity(wash)
        }
        return .clear
    }

    private func rowInset(depth: Int, aligns: Bool) -> EdgeInsets {
        let leading = QuietBeauty.pageInset + CGFloat(depth) * 18 + (aligns ? LibraryRow.chevronColumn : 0)
        return EdgeInsets(top: 0, leading: leading, bottom: 0, trailing: QuietBeauty.pageInset)
    }

    private func toggleFolder(_ path: String) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) {
            if expandedFolders.contains(path) {
                expandedFolders.remove(path)
            } else {
                expandedFolders.insert(path)
            }
        }
    }

    private func searchSubtitle(_ record: ReadingRecord) -> String {
        guard let relative = record.relativePath else { return record.subtitle }
        let parent = (relative as NSString).deletingLastPathComponent
        guard !parent.isEmpty else { return record.subtitle }
        return "\(parent)  ·  \(ReadingDate.quiet(record.lastOpened))  ·  \(ReadingDate.bytes(record.byteCount))"
    }

    private var emptyLibrary: some View {
        VStack(alignment: .leading, spacing: 18) {
            InkRule(width: QuietBeauty.ruleWidthEmpty)
            Text("把文稿交给素笺")
                .inkSongti(QuietBeauty.emptyTitleSize, relativeTo: .largeTitle)
                .foregroundStyle(Ink.primary)
            Text("「文件」里的 Markdown，在这里按纸页来读。标题、表格和代码都会排好。")
                .font(.system(size: QuietBeauty.proseSize))
                .foregroundStyle(Ink.soft)
                .lineSpacing(QuietBeauty.proseLineSpacing)
            Button {
                importing = true
            } label: {
                Text("打开文稿")
                    .font(.system(size: QuietBeauty.proseSize, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .overlay {
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Ink.bronze, lineWidth: QuietBeauty.controlStroke)
                    }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Ink.primary)
            .padding(.top, 6)
            Text(importHint)
                .font(.system(size: 13))
                .foregroundStyle(Ink.soft)
                .lineSpacing(3)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var importHint: String {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return String(localized: "在「文件」中打开一份 .md，点分享，选择素笺。\n也可以把文稿放进「我的 iPad › 素笺」。")
        }
        return String(localized: "在「文件」中打开一份 .md，点分享，选择素笺。\n也可以把文稿放进「我的 iPhone › 素笺」。")
    }

    private var missingSearch: some View {
        VStack(spacing: 0) {
            if isSelecting { masthead }
            Text("没有符合的文稿")
                .inkSongti(QuietBeauty.listTitleSize)
                .foregroundStyle(Ink.soft)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ReaderPlaceholder: View {
    var showsSidebarButton: Bool
    var onToggleLibrary: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            InkRule(width: QuietBeauty.ruleWidthEmpty)
            Text("选择一篇文稿")
                .inkSongti(QuietBeauty.emptyTitleSize, relativeTo: .largeTitle)
                .foregroundStyle(Ink.primary)
            Text("点开文库里的记录，就在这里读。")
                .font(.system(size: QuietBeauty.proseSize))
                .foregroundStyle(Ink.soft)
                .lineSpacing(QuietBeauty.proseLineSpacing)
        }
        .frame(maxWidth: 420, alignment: .leading)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            if showsSidebarButton {
                Button(action: onToggleLibrary) {
                    Image(systemName: "sidebar.leading")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Ink.chrome(active: false))
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel(Text("文库"))
                .padding(.leading, 16)
                .padding(.top, 4)
                .topChromeInset()
            }
        }
    }
}
