import Cocoa

struct MatchRow {
    let item: WindowItem
    let match: Match?
}

/// Actions reachable from the switcher search field. An exact keyword (`settings`, `设置`) sorts above windows.
struct SwitcherCommand {
    enum Action {
        case openSettings
    }

    let id: String
    let title: String
    let subtitle: String
    let symbolName: String
    let keywords: [String]
    let action: Action

    /// Word-prefix tier in `Matcher`. Substring, acronym, and subsequence hits stay out of the command list.
    private static let wordPrefixScore = 700

    func match(query: String) -> Match? {
        var best: Match?
        for keyword in keywords {
            guard let found = Matcher.match(query: query, app: "", title: keyword),
                  found.score >= Self.wordPrefixScore else { continue }
            if found.score > (best?.score ?? -1) { best = found }
        }
        return best
    }

    func isExact(_ query: String) -> Bool {
        let folded = Self.fold(query)
        return keywords.contains { Self.fold($0) == folded }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "en_US"))
    }

    static let settings = SwitcherCommand(
        id: "settings",
        title: "设置",
        subtitle: "打开 hei 设置",
        symbolName: "gearshape",
        keywords: ["设置", "settings", "setting", "preferences", "prefs"],
        action: .openSettings)

    static let all = [settings]
}

private enum SearchResult {
    case window(MatchRow)
    case command(SwitcherCommand, score: Int, exact: Bool)

    var score: Int {
        switch self {
        case .window(let row): return row.match?.score ?? 0
        case .command(_, let score, _): return score
        }
    }

    var isExact: Bool {
        if case .command(_, _, let exact) = self { return exact }
        return false
    }

    var isCommand: Bool {
        if case .command = self { return true }
        return false
    }

    var identity: String {
        switch self {
        case .window(let row): return "window:\(row.item.key)"
        case .command(let command, _, _): return "command:\(command.id)"
        }
    }
}

final class SwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class SwitcherController: NSObject, NSTableViewDataSource, NSTableViewDelegate,
                                NSTextFieldDelegate, NSWindowDelegate {
    private var theme = Theme.current
    private let maxRows = 9
    private let bannerHeight: CGFloat = 96

    private let panel: SwitcherPanel
    private let effect = DragEffectView()
    private let searchIcon = PassThroughImageView()
    private let field = DragTextField()
    private let table = DragTableView()
    private let scroll = NSScrollView()
    private let sectionLabel = DragLabel(labelWithString: "")
    private let hintBar = HintBar()
    private let divider = NSView()
    private let banner = DragView()
    private let closeButton = NSButton()
    private let bannerLine1 = NSTextField(labelWithString: "")
    private let bannerLine2 = NSTextField(labelWithString: "")
    private let settingsButton = NSButton(title: "打开系统设置", target: nil, action: nil)
    private let retryButton = NSButton(title: "重新检测", target: nil, action: nil)
    private let resetButton = NSButton(title: "重置授权", target: nil, action: nil)

    private var items: [WindowItem] = []
    private var results: [SearchResult] = []
    private var placeholder: String? = "正在读取窗口…"
    private var generation = 0
    private var previousApp: NSRunningApplication?
    private var iconCache: [pid_t: NSImage] = [:]
    private var didPromptPermission = false
    private var permissionTimer: Timer?
    private var positioningPanel = false
    private var userMovedPanel = false

    override init() {
        panel = SwitcherPanel(contentRect: NSRect(x: 0, y: 0, width: Theme.current.width, height: 320),
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered,
                              defer: false)
        super.init()
        configurePanel()
        configureViews()
        layoutViews()
    }

    // MARK: - Setup

    private func configurePanel() {
        panel.delegate = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .none
        NotificationCenter.default.addObserver(self, selector: #selector(panelDidMove),
                                               name: NSWindow.didMoveNotification, object: panel)
        panel.isReleasedWhenClosed = false

        let content = ThemedContentView(frame: NSRect(x: 0, y: 0, width: Theme.current.width, height: 320))
        content.wantsLayer = true
        content.layer?.cornerRadius = 14
        content.layer?.masksToBounds = true
        content.layer?.borderWidth = 1
        content.onAppearanceChange = { [weak self] in self?.applyPreferences() }
        panel.contentView = content
    }

    private func configureViews() {
        guard let content = panel.contentView else { return }

        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        content.addSubview(effect)

        searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        searchIcon.contentTintColor = .secondaryLabelColor
        searchIcon.imageScaling = .scaleProportionallyDown
        content.addSubview(searchIcon)

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = theme.searchFont
        field.textColor = .labelColor
        field.placeholderString = "嘿，找哪个窗口？"
        field.delegate = self
        field.usesSingleLineMode = true
        field.maximumNumberOfLines = 1
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        content.addSubview(field)

        table.headerView = nil
        table.rowHeight = theme.rowHeight
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        table.allowsEmptySelection = true
        table.focusRingType = .none
        table.refusesFirstResponder = true
        table.style = .plain
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("window"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)

        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.verticalScrollElasticity = .none
        scroll.borderType = .noBorder
        content.addSubview(scroll)

        sectionLabel.font = .systemFont(ofSize: 12, weight: .medium)
        sectionLabel.textColor = .tertiaryLabelColor
        sectionLabel.isHidden = !theme.sectionHeader
        content.addSubview(sectionLabel)

        hintBar.theme = theme
        content.addSubview(hintBar)

        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.38).cgColor
        divider.isHidden = !theme.divider
        content.addSubview(divider)

        banner.isHidden = true
        for (label, text) in [(bannerLine1, "需要「辅助功能」权限，才能读取并切换其他应用的窗口。"),
                              (bannerLine2, "开关已打开仍不生效？点「重置授权」，再重新勾选。")] {
            label.stringValue = text
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
            label.alignment = .left
            label.lineBreakMode = .byTruncatingTail
            label.usesSingleLineMode = true
            banner.addSubview(label)
        }

        settingsButton.bezelStyle = .rounded
        settingsButton.controlSize = .small
        settingsButton.target = self
        settingsButton.action = #selector(openSettings)
        banner.addSubview(settingsButton)

        retryButton.bezelStyle = .rounded
        retryButton.controlSize = .small
        retryButton.target = self
        retryButton.action = #selector(retryPermission)
        banner.addSubview(retryButton)

        resetButton.bezelStyle = .rounded
        resetButton.controlSize = .small
        resetButton.target = self
        resetButton.action = #selector(resetPermission)
        banner.addSubview(resetButton)

        content.addSubview(banner)

        closeButton.isBordered = false
        closeButton.bezelStyle = .inline
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "关闭")
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.toolTip = "关闭"
        closeButton.target = self
        closeButton.action = #selector(closePanel)
        closeButton.isHidden = true
        content.addSubview(closeButton)
    }

    // MARK: - Show / hide

    /// Re-reads the theme from preferences and repaints. Called on show, on a settings change, and when the
    /// system flips light/dark while the panel is alive (the layer border is a CGColor and must be reset).
    func applyPreferences() {
        let dark = panel.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let next = Prefs.theme(forDark: dark)
        if next.id != theme.id {
            theme = next
            hintBar.theme = next
            field.font = next.searchFont
            table.rowHeight = next.rowHeight
            table.reloadData()
            if panel.isVisible { layoutViews() }
        }
        applyChromeColors()
    }

    private func applyChromeColors() {
        guard let content = panel.contentView else { return }
        content.layer?.cornerRadius = theme.cornerRadius
        content.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
        divider.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.38).cgColor
        hintBar.needsDisplay = true
        table.reloadData()
    }

    func toggle() {
        if panel.isVisible { hide(restoreFocus: false) } else { show() }
    }

    func show() {
        applyPreferences()
        previousApp = NSWorkspace.shared.frontmostApplication
        generation += 1
        field.stringValue = Runtime.demoQuery ?? ""
        userMovedPanel = false
        items = []
        results = []
        let ready = Permissions.isTrusted || Runtime.mock
        placeholder = ready ? "正在读取窗口…" : nil
        banner.isHidden = ready
        table.reloadData()
        layoutViews()
        positionPanel()

        panel.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
        Log.write("panel shown trusted=\(Permissions.isTrusted) windowNumber=\(panel.windowNumber) frame=\(NSStringFromRect(panel.frame))")
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.07
            panel.animator().alphaValue = 1
        }

        if !Permissions.isTrusted && !didPromptPermission && !Runtime.quiet && !Runtime.mock {
            didPromptPermission = true
            Permissions.requestPrompt()
        }
        refreshWindows()
        if !Permissions.isTrusted { startPermissionWatch() }
    }

    private func hide(restoreFocus: Bool) {
        guard panel.isVisible else { return }
        permissionTimer?.invalidate()
        permissionTimer = nil
        generation += 1
        panel.orderOut(nil)
        if restoreFocus, let app = previousApp, app.processIdentifier != getpid() {
            app.activate(options: [])
        }
    }

    /// Renders the panel offscreen. Used by `--snapshot` to inspect layout without Screen Recording permission;
    /// the NSVisualEffectView backdrop does not render offscreen, so a solid color is composited underneath.
    func snapshot(to path: String) {
        guard let view = panel.contentView else { return }
        view.layoutSubtreeIfNeeded()
        let size = view.bounds.size
        if Runtime.alpha { effect.isHidden = true }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let png: Data?
        if Runtime.alpha {
            png = rep.representation(using: .png, properties: [:])
        } else {
            let image = NSImage(size: size)
            image.lockFocus()
            NSColor.windowBackgroundColor.setFill()
            NSRect(origin: .zero, size: size).fill()
            rep.draw(in: NSRect(origin: .zero, size: size))
            image.unlockFocus()
            png = image.tiffRepresentation
                .flatMap { NSBitmapImageRep(data: $0) }?
                .representation(using: .png, properties: [:])
        }
        if let png { try? png.write(to: URL(fileURLWithPath: path)) }
        Log.write("snapshot \(path) size=\(size) rows=\(results.count) theme=\(theme.id) alpha=\(Runtime.alpha)")
        NSApp.terminate(nil)
    }

    /// While the permission panel is up, watch for the user flipping the switch in System Settings so the
    /// list appears without quitting and relaunching.
    private func startPermissionWatch() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard self.panel.isVisible else { return }
            guard Permissions.isTrusted else { return }
            timer.invalidate()
            self.permissionTimer = nil
            Log.write("permission granted while panel was open")
            self.setBannerVisible(false)
            self.refreshWindows()
        }
    }

    private func refreshWindows() {
        if Runtime.mock {
            items = MockData.items
            placeholder = nil
            applyFilter(resetSelection: false)
            return
        }
        guard Permissions.isTrusted else {
            setBannerVisible(true)
            return
        }
        setBannerVisible(false)
        let current = generation
        WindowScanner.shared.scan { [weak self] scanned in
            guard let self, self.generation == current else { return }
            self.items = scanned
            self.placeholder = nil
            Log.write("scan found \(scanned.count) windows")
            self.applyFilter(resetSelection: false)
        }
    }

    private func setBannerVisible(_ visible: Bool) {
        Log.write("permission banner visible=\(visible)")
        banner.isHidden = !visible
        if visible {
            results = []
            table.reloadData()
        }
        layoutViews()
    }

    // MARK: - Filtering

    private func applyFilter(resetSelection: Bool) {
        let previousKey = selectedIdentity()
        let query = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        results = searchResults(query: query)

        placeholder = results.isEmpty ? (query.isEmpty ? "没有可切换的窗口" : "没有匹配的窗口") : nil
        table.reloadData()
        layoutViews()

        guard !results.isEmpty else {
            table.deselectAll(nil)
            return
        }
        if !resetSelection, let key = previousKey, let index = results.firstIndex(where: { $0.identity == key }) {
            select(index)
        } else {
            select(0)
        }
    }

    /// Exact command keywords stay above every window. Weaker command hits compete by score and lose ties to windows.
    private func searchResults(query: String) -> [SearchResult] {
        if query.isEmpty {
            return items.map { .window(MatchRow(item: $0, match: nil)) }
        }
        let windows = items.compactMap { item -> SearchResult? in
            Matcher.match(query: query, app: item.appName, title: item.title)
                .map { .window(MatchRow(item: item, match: $0)) }
        }.sorted { $0.score > $1.score }
        let commands = SwitcherCommand.all.compactMap { command -> SearchResult? in
            command.match(query: query).map { .command(command, score: $0.score, exact: command.isExact(query)) }
        }
        let exact = commands.filter(\.isExact).sorted { $0.score > $1.score }
        let rest = (windows + commands.filter { !$0.isExact }).sorted { $0.score > $1.score }
        return exact + rest
    }

    private func selectedIdentity() -> String? {
        let row = table.selectedRow
        guard row >= 0, row < results.count else { return nil }
        return results[row].identity
    }

    private func select(_ index: Int) {
        guard index >= 0, index < results.count else { return }
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        table.scrollRowToVisible(index)
    }

    private func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        let current = table.selectedRow >= 0 ? table.selectedRow : 0
        let next = (current + delta + results.count) % results.count
        select(next)
    }

    private func commitSelection() {
        let row = table.selectedRow
        guard row >= 0, row < results.count else { return }
        switch results[row] {
        case .window(let matchRow):
            let item = matchRow.item
            Log.write("focus pid=\(item.pid) wid=\(item.wid.map(String.init) ?? "-") title=\(item.title)")
            hide(restoreFocus: false)
            guard !Runtime.mock else { return }
            Flipper.focus(item)
        case .command(let command, _, _):
            run(command)
        }
    }

    private func run(_ command: SwitcherCommand) {
        Log.write("command \(command.id)")
        hide(restoreFocus: false)
        switch command.action {
        case .openSettings:
            NotificationCenter.default.post(name: .heiOpenSettings, object: nil)
        }
    }

    // MARK: - Layout

    private var showsSectionHeader: Bool {
        theme.sectionHeader && banner.isHidden && !results.contains(where: \.isCommand)
    }

    private var windowCount: Int {
        results.reduce(0) { count, result in
            if case .window = result { return count + 1 }
            return count
        }
    }

    private func contentHeight() -> CGFloat {
        if !banner.isHidden { return theme.searchHeight + bannerHeight + theme.footerHeight }
        let visibleRows = results.isEmpty ? 1 : min(results.count, maxRows)
        let header: CGFloat = theme.sectionHeader ? 26 : 0
        return theme.searchHeight + header + CGFloat(visibleRows) * theme.rowHeight + 12 + theme.footerHeight
    }

    private func layoutViews() {
        let oldTop = panel.frame.maxY
        let height = contentHeight()
        positioningPanel = true
        panel.setContentSize(NSSize(width: theme.width, height: height))
        if panel.isVisible {
            panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: oldTop - height))
        }
        positioningPanel = false
        let showsClose = !banner.isHidden
        closeButton.isHidden = !showsClose
        guard let content = panel.contentView else { return }
        content.frame = NSRect(x: 0, y: 0, width: theme.width, height: height)
        effect.frame = content.bounds

        let searchMid = height - theme.searchHeight / 2
        let searchIconSize: CGFloat = theme.singleLine ? 19 : 17
        searchIcon.frame = NSRect(x: theme.iconLeading + 2, y: searchMid - searchIconSize / 2,
                                  width: searchIconSize, height: searchIconSize)
        let fieldTrailing: CGFloat = showsClose ? 52 : 20
        field.frame = NSRect(x: theme.textLeading - 2, y: searchMid - 14,
                             width: theme.width - theme.textLeading - fieldTrailing, height: 28)
        closeButton.frame = NSRect(x: theme.width - 42, y: searchMid - 11, width: 22, height: 22)

        let headerHeight: CGFloat = theme.sectionHeader ? 26 : 0
        let bodyHeight = height - theme.searchHeight - theme.footerHeight
        let listHeight = bodyHeight - headerHeight
        let bodyFrame = NSRect(x: 0, y: theme.footerHeight, width: theme.width, height: listHeight)
        // The section label occupies the same band as the permission copy. Drawing both mixes the glyphs.
        sectionLabel.isHidden = !showsSectionHeader
        if showsSectionHeader {
            sectionLabel.stringValue = "\(results.count) 个窗口"
            sectionLabel.frame = NSRect(x: theme.iconLeading + 2, y: height - theme.searchHeight - 22,
                                        width: theme.width - 40, height: 18)
        }

        divider.isHidden = !theme.divider
        divider.frame = NSRect(x: 12, y: height - theme.searchHeight, width: theme.width - 24, height: 1)

        if banner.isHidden {
            scroll.isHidden = false
            scroll.frame = bodyFrame
            let tableHeight = max(CGFloat(max(results.count, 1)) * theme.rowHeight + 10, bodyHeight)
            table.frame = NSRect(x: 0, y: 0, width: bodyFrame.width, height: tableHeight)
            table.tableColumns.first?.width = bodyFrame.width
        } else {
            scroll.isHidden = true
            let bannerArea = bodyHeight - 8
            banner.frame = NSRect(x: 20, y: theme.footerHeight + 8, width: theme.width - 40, height: bannerArea)
            bannerLine1.frame = NSRect(x: 0, y: bannerArea - 26, width: banner.frame.width, height: 17)
            bannerLine2.frame = NSRect(x: 0, y: bannerArea - 45, width: banner.frame.width, height: 17)
            settingsButton.frame = NSRect(x: banner.frame.width - 116, y: 2, width: 116, height: 26)
            retryButton.frame = NSRect(x: banner.frame.width - 204, y: 2, width: 80, height: 26)
            resetButton.frame = NSRect(x: banner.frame.width - 296, y: 2, width: 84, height: 26)
        }

        hintBar.isHidden = !banner.isHidden
        hintBar.frame = NSRect(x: 0, y: 0, width: theme.width, height: theme.footerHeight)
        hintBar.leftText = theme.showCount ? "\(windowCount) 个窗口" : ""
        hintBar.needsDisplay = true

        content.layoutSubtreeIfNeeded()
        if !banner.isHidden {
            Log.write("banner layout h=\(height) field=\(NSStringFromRect(field.frame)) l1=\(NSStringFromRect(bannerLine1.frame)) l2=\(NSStringFromRect(bannerLine2.frame)) banner=\(NSStringFromRect(banner.frame))")
        }
    }

    private func positionPanel() {
        guard !userMovedPanel else { return }
        let size = panel.frame.size
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let x = (visible.midX - size.width / 2).rounded()
        let y = (visible.maxY - size.height - min(170, visible.height * 0.18)).rounded()
        movePanel(to: NSPoint(x: x, y: y))
    }

    private func movePanel(to origin: NSPoint) {
        positioningPanel = true
        panel.setFrameOrigin(origin)
        positioningPanel = false
    }

    @objc private func panelDidMove(_ notification: Notification) {
        guard panel.isVisible, !positioningPanel else { return }
        userMovedPanel = true
    }

    @objc private func closePanel() {
        hide(restoreFocus: true)
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        max(results.count, 1)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard !results.isEmpty else {
            let cell = MessageCell(width: theme.width, theme: theme)
            cell.label.stringValue = placeholder ?? ""
            return cell
        }
        switch results[row] {
        case .window(let matchRow):
            let cell = WindowCell(width: theme.width, theme: theme)
            cell.configure(title: matchRow.item.title,
                           app: matchRow.item.appName,
                           icon: icon(for: matchRow.item),
                           titleSpans: matchRow.match?.titleSpans ?? [],
                           appSpans: matchRow.match?.appSpans ?? [],
                           minimized: matchRow.item.isMinimized)
            return cell
        case .command(let command, _, let exact):
            let cell = WindowCell(width: theme.width, theme: theme)
            let titleCount = Array(command.title).count
            cell.configure(title: command.title,
                           app: command.subtitle,
                           icon: commandIcon(command),
                           titleSpans: exact ? [0..<titleCount] : [],
                           appSpans: [],
                           minimized: false)
            return cell
        }
    }

    private func commandIcon(_ command: SwitcherCommand) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: theme.iconSize * 0.62, weight: .regular)
        let image = NSImage(systemSymbolName: command.symbolName, accessibilityDescription: command.title)?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        RowView(theme: theme)
    }

    private func icon(for item: WindowItem) -> NSImage? {
        if let cached = iconCache[item.pid] { return cached }
        guard let app = NSRunningApplication(processIdentifier: item.pid), let icon = app.icon else { return nil }
        iconCache[item.pid] = icon
        return icon
    }

    // MARK: - Input

    func controlTextDidChange(_ obj: Notification) {
        applyFilter(resetSelection: true)
        revealExactCommand()
    }

    /// While the permission banner covers the list, an exact command keyword still has to be reachable.
    private func revealExactCommand() {
        guard !Permissions.isTrusted, !Runtime.mock else { return }
        let query = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let exact = SwitcherCommand.all.contains { $0.isExact(query) }
        if exact == banner.isHidden { return }
        setBannerVisible(!exact)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(-1)
            return true
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(1)
            return true
        case #selector(NSResponder.insertTab(_:)):
            moveSelection(1)
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            moveSelection(-1)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            commitSelection()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            hide(restoreFocus: true)
            return true
        default:
            return false
        }
    }

    @objc private func rowClicked() {
        let row = table.clickedRow
        guard row >= 0, row < results.count else { return }
        select(row)
        commitSelection()
    }

    @objc private func openSettings() {
        Permissions.openAccessibilitySettings()
    }

    @objc private func resetPermission() {
        _ = Permissions.resetAccessibility()
        didPromptPermission = false
        Permissions.requestPrompt()
    }

    @objc private func retryPermission() {
        if Permissions.isTrusted {
            setBannerVisible(false)
            refreshWindows()
        } else {
            Permissions.requestPrompt()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard notification.object as? NSWindow === panel else { return }
        // Deferred: a re-summon can re-key the panel in the same runloop turn.
        DispatchQueue.main.async {
            guard self.panel.isVisible, !self.panel.isKeyWindow else { return }
            self.hide(restoreFocus: false)
        }
    }
}

private final class DragEffectView: NSVisualEffectView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

private final class PassThroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A click still focuses the field. Moving the pointer starts a window drag.
private final class DragTextField: NSTextField {
    private static let dragSlop: CGFloat = 3

    override func mouseDown(with event: NSEvent) {
        let start = event.locationInWindow
        var dragged = false
        window?.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: .infinity, mode: .eventTracking) { next, stop in
            guard let next else { return }
            if next.type == .leftMouseUp {
                stop.pointee = true
                return
            }
            let dx = next.locationInWindow.x - start.x
            let dy = next.locationInWindow.y - start.y
            if hypot(dx, dy) > Self.dragSlop {
                dragged = true
                stop.pointee = true
                self.window?.performDrag(with: next)
            }
        }
        if !dragged {
            super.mouseDown(with: event)
        }
    }
}

private final class DragLabel: NSTextField {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

private final class DragTableView: NSTableView {
    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        if row(at: local) < 0 {
            window?.performDrag(with: event)
            return
        }
        super.mouseDown(with: event)
    }
}

private final class DragView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if hit is NSTextField { return self }
        return hit
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

final class ThemedContentView: NSView {
    var onAppearanceChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
}

// MARK: - Cells

private final class WindowCell: NSTableCellView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let appLabel = NSTextField(labelWithString: "")
    private let theme: Theme

    init(width: CGFloat, theme: Theme) {
        self.theme = theme
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: theme.rowHeight))
        iconView.frame = NSRect(x: theme.iconLeading, y: (theme.rowHeight - theme.iconSize) / 2,
                                width: theme.iconSize, height: theme.iconSize)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        if theme.singleLine {
            let metaX = width * 0.62
            titleLabel.frame = NSRect(x: theme.textLeading, y: (theme.rowHeight - 21) / 2,
                                      width: (theme.metaColumn ? metaX : width) - theme.textLeading - 16,
                                      height: 21)
            titleLabel.lineBreakMode = .byTruncatingTail
            addSubview(titleLabel)

            appLabel.frame = NSRect(x: metaX, y: (theme.rowHeight - 18) / 2,
                                    width: width - metaX - theme.iconLeading, height: 18)
            appLabel.alignment = .right
            appLabel.lineBreakMode = .byTruncatingTail
            addSubview(appLabel)
        } else {
            let textWidth = width - theme.textLeading - 18
            titleLabel.frame = NSRect(x: theme.textLeading, y: theme.rowHeight - 24, width: textWidth, height: 19)
            titleLabel.lineBreakMode = .byTruncatingTail
            addSubview(titleLabel)

            appLabel.frame = NSRect(x: theme.textLeading, y: 7, width: textWidth, height: 15)
            appLabel.lineBreakMode = .byTruncatingTail
            addSubview(appLabel)
        }
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    func configure(title: String, app: String, icon: NSImage?,
                   titleSpans: [Range<Int>], appSpans: [Range<Int>], minimized: Bool) {
        iconView.image = icon ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        iconView.contentTintColor = iconView.image?.isTemplate == true ? .secondaryLabelColor : nil
        let prefix = minimized ? "▪ " : ""
        titleLabel.attributedStringValue = Self.attributed(prefix + title, spans: titleSpans, offset: prefix.count,
                                                           font: theme.titleFont, color: .labelColor)
        appLabel.attributedStringValue = Self.attributed(app, spans: appSpans, offset: 0,
                                                         font: theme.subtitleFont,
                                                         color: theme.singleLine ? .tertiaryLabelColor : .secondaryLabelColor,
                                                         alignment: theme.singleLine ? .right : .left)
    }

    private static func attributed(_ text: String, spans: [Range<Int>], offset: Int,
                                   font: NSFont, color: NSColor,
                                   alignment: NSTextAlignment = .left) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        let result = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: color,
                                                                          .paragraphStyle: paragraph])
        var location = 0
        for (index, character) in Array(text).enumerated() {
            let length = String(character).utf16.count
            if spans.contains(where: { $0.contains(index - offset) }) {
                result.addAttributes([.font: NSFont.systemFont(ofSize: font.pointSize, weight: .semibold),
                                      .foregroundColor: NSColor.controlAccentColor],
                                     range: NSRange(location: location, length: length))
            }
            location += length
        }
        return result
    }
}

private final class MessageCell: NSTableCellView {
    let label = NSTextField(labelWithString: "")

    init(width: CGFloat, theme: Theme) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: theme.rowHeight))
        label.frame = NSRect(x: 16, y: (theme.rowHeight - 18) / 2, width: width - 32, height: 18)
        label.alignment = .center
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }
}

private final class RowView: NSTableRowView {
    private let theme: Theme

    init(theme: Theme) {
        self.theme = theme
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none, isSelected else { return }
        let rect = bounds.insetBy(dx: theme.selectionInset, dy: 3)
        if theme.neutralSelection {
            NSColor.labelColor.withAlphaComponent(isEmphasized ? 0.10 : 0.06).setFill()
            NSBezierPath(roundedRect: rect, xRadius: theme.selectionRadius, yRadius: theme.selectionRadius).fill()
            return
        }
        if theme.selectionBar {
            NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: rect, xRadius: theme.selectionRadius, yRadius: theme.selectionRadius).fill()
            let bar = NSRect(x: rect.minX + 6, y: rect.midY - 9, width: 3, height: 18)
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
        } else {
            let alpha = theme.selectionFill * (isEmphasized ? 1 : 0.6)
            NSColor.controlAccentColor.withAlphaComponent(alpha).setFill()
            NSBezierPath(roundedRect: rect, xRadius: theme.selectionRadius, yRadius: theme.selectionRadius).fill()
            NSColor.white.withAlphaComponent(0.12).setStroke()
            let stroke = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                      xRadius: theme.selectionRadius, yRadius: theme.selectionRadius)
            stroke.lineWidth = 1
            stroke.stroke()
        }
    }
}
