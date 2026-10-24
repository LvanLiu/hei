import Cocoa
import ServiceManagement

extension Notification.Name {
    static let heiPreferencesChanged = Notification.Name("heiPreferencesChanged")
    static let heiOpenSettings = Notification.Name("heiOpenSettings")
}

/// UserDefaults-backed settings shared by the switcher and the settings window.
enum Prefs {
    private static let defaults = UserDefaults.standard

    static var followSystem: Bool {
        get { defaults.object(forKey: "followSystem") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "followSystem"); notify() }
    }
    static var darkTheme: String {
        get { defaults.string(forKey: "darkTheme") ?? "launcher" }
        set { defaults.set(newValue, forKey: "darkTheme"); notify() }
    }
    static var lightTheme: String {
        get { defaults.string(forKey: "lightTheme") ?? "launcher" }
        set { defaults.set(newValue, forKey: "lightTheme"); notify() }
    }
    static var fixedTheme: String {
        get { defaults.string(forKey: "fixedTheme") ?? "launcher" }
        set { defaults.set(newValue, forKey: "fixedTheme"); notify() }
    }
    static var showMenuBarIcon: Bool {
        get { defaults.object(forKey: "showMenuBarIcon") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showMenuBarIcon"); notify() }
    }

    static func theme(forDark dark: Bool) -> Theme {
        Theme.named(followSystem ? (dark ? darkTheme : lightTheme) : fixedTheme)
    }

    private static func notify() {
        NotificationCenter.default.post(name: .heiPreferencesChanged, object: nil)
    }
}

enum ThemeCatalog {
    static let all: [(id: String, name: String)] = [
        ("launcher", "启动器"),
        ("glass", "玻璃"),
        ("minimal", "极简"),
        ("classic", "经典"),
    ]
}

// MARK: - Window

final class SettingsWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            close()
            return
        }
        super.keyDown(with: event)
    }
}

private enum SettingsMetrics {
    static let size = NSSize(width: 760, height: 500)
    static let sidebarWidth: CGFloat = 188
    static let contentInset: CGFloat = 28
    static let titlebarInset: CGFloat = 56
}

final class SettingsWindowController: NSWindowController {
    private let settingsViewController = SettingsViewController()

    convenience init() {
        let window = SettingsWindow(contentRect: NSRect(origin: .zero, size: SettingsMetrics.size),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered,
                              defer: false)
        window.title = "hei 设置"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        window.center()
        self.init(window: window)
        contentViewController = settingsViewController
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Offscreen render for design review; the window's visual-effect sidebar comes out transparent.
    func snapshot(to path: String) {
        guard let view = window?.contentView else { return }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
        Log.write("settings snapshot \(path)")
        NSApp.terminate(nil)
    }
}

// MARK: - Layout primitives

class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class CardView: FlippedView {
    init(width: CGFloat, height: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }

    required init?(coder: NSCoder) { fatalError("not supported") }
}

// MARK: - Settings

private struct SettingsSection {
    let id: String
    let title: String
    let icon: String
}

final class SettingsViewController: NSViewController {
    private let sections: [SettingsSection] = [
        SettingsSection(id: "general", title: "通用", icon: "gearshape"),
        SettingsSection(id: "appearance", title: "外观", icon: "paintpalette"),
        SettingsSection(id: "shortcuts", title: "快捷键", icon: "command"),
        SettingsSection(id: "about", title: "关于", icon: "info.circle"),
    ]
    private let sidebarWidth = SettingsMetrics.sidebarWidth
    private var selectedSection = 0
    private var laidOutWidth: CGFloat = 0

    private let sidebarTable = NSTableView()
    private let sidebarScroll = NSScrollView()
    private let contentScroll = NSScrollView()
    private let contentContainer = FlippedView()

    override func loadView() {
        let root = NSView(frame: NSRect(origin: .zero, size: SettingsMetrics.size))
        view = root

        let sidebar = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: sidebarWidth, height: root.bounds.height))
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .active
        sidebar.autoresizingMask = [.height]
        root.addSubview(sidebar)

        sidebarTable.headerView = nil
        sidebarTable.style = .sourceList
        sidebarTable.rowHeight = 34
        sidebarTable.backgroundColor = .clear
        sidebarTable.selectionHighlightStyle = .none
        sidebarTable.dataSource = self
        sidebarTable.delegate = self
        sidebarTable.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("section")))
        sidebarTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)

        sidebarScroll.documentView = sidebarTable
        sidebarScroll.drawsBackground = false
        sidebarScroll.hasVerticalScroller = false
        sidebarScroll.frame = sidebarScrollFrame(in: root.bounds)
        sidebarScroll.autoresizingMask = [.height]
        sidebar.addSubview(sidebarScroll)

        contentScroll.drawsBackground = true
        contentScroll.backgroundColor = .windowBackgroundColor
        contentScroll.hasVerticalScroller = true
        contentScroll.autohidesScrollers = true
        contentScroll.frame = NSRect(x: sidebarWidth, y: 0, width: root.bounds.width - sidebarWidth,
                                     height: root.bounds.height)
        contentScroll.autoresizingMask = [.width, .height]
        contentScroll.documentView = contentContainer
        root.addSubview(contentScroll)

    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if let index = CommandLine.arguments.firstIndex(of: "--settings-section"),
           index + 1 < CommandLine.arguments.count,
           let section = sections.firstIndex(where: { $0.id == CommandLine.arguments[index + 1] }) {
            selectedSection = section
            sidebarTable.selectRowIndexes(IndexSet(integer: section), byExtendingSelection: false)
        }
        DispatchQueue.main.async {
            self.sidebarTable.reloadData()
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        sidebarScroll.frame = sidebarScrollFrame(in: view.bounds)
        let width = view.bounds.width
        guard abs(width - laidOutWidth) > 0.5 else { return }
        laidOutWidth = width
        reloadContent()
    }

    private func sidebarScrollFrame(in bounds: NSRect) -> NSRect {
        NSRect(x: 8, y: 12, width: sidebarWidth - 16, height: bounds.height - SettingsMetrics.titlebarInset - 8)
    }

    // MARK: Content

    private func reloadContent() {
        contentContainer.subviews.forEach { $0.removeFromSuperview() }

        let width = view.bounds.width - sidebarWidth
        let cardWidth = width - SettingsMetrics.contentInset * 2
        var y = SettingsMetrics.titlebarInset

        let header = NSTextField(labelWithString: sections[selectedSection].title)
        header.font = .systemFont(ofSize: 20, weight: .semibold)
        header.frame = NSRect(x: SettingsMetrics.contentInset, y: y, width: cardWidth, height: 28)
        contentContainer.addSubview(header)
        y += 44

        switch sections[selectedSection].id {
        case "general": y = buildGeneral(width: cardWidth, top: y)
        case "appearance": y = buildAppearance(width: cardWidth, top: y)
        case "shortcuts": y = buildShortcuts(width: cardWidth, top: y)
        default: y = buildAbout(width: cardWidth, top: y)
        }
        y += 28

        contentContainer.frame = NSRect(x: 0, y: 0, width: width, height: max(y, view.bounds.height))
    }

    private func card(rows: [NSView], width: CGFloat, top: CGFloat) -> CGFloat {
        let height = rows.reduce(CGFloat(0)) { $0 + $1.frame.height }
        let container = CardView(width: width, height: height)
        container.frame.origin = NSPoint(x: SettingsMetrics.contentInset, y: top)
        var offset: CGFloat = 0
        for (index, row) in rows.enumerated() {
            row.frame.origin = NSPoint(x: 0, y: offset)
            row.frame.size.width = width
            (row as? SettingRow)?.layout(width: width)
            container.addSubview(row)
            if index < rows.count - 1 {
                let line = NSView(frame: NSRect(x: 16, y: offset + row.frame.height - 1, width: width - 32, height: 1))
                line.wantsLayer = true
                line.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
                container.addSubview(line)
            }
            offset += row.frame.height
        }
        contentContainer.addSubview(container)
        return top + height + 22
    }

    private func makeRow(title: String, subtitle: String?, control: NSControl) -> SettingRow {
        SettingRow(title: title, subtitle: subtitle, control: control)
    }

    private func toggle(_ on: Bool, action: Selector) -> NSSwitch {
        let toggle = NSSwitch()
        toggle.state = on ? .on : .off
        toggle.target = self
        toggle.action = action
        return toggle
    }

    private func popup(_ items: [(String, String)], selected: String, action: Selector) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        for item in items {
            button.addItem(withTitle: item.1)
            button.lastItem?.representedObject = item.0
        }
        if let index = items.firstIndex(where: { $0.0 == selected }) {
            button.selectItem(at: index)
        }
        button.target = self
        button.action = action
        return button
    }

    private func note(_ text: String, width: CGFloat, top: CGFloat) -> CGFloat {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = width
        let height = ceil(label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 400)).height ?? 16)
        label.frame = NSRect(x: SettingsMetrics.contentInset, y: top, width: width, height: height)
        contentContainer.addSubview(label)
        return top + height + 16
    }

    // MARK: Sections

    private func buildGeneral(width: CGFloat, top: CGFloat) -> CGFloat {
        let login = toggle(LaunchAtLogin.isEnabled, action: #selector(toggleLogin))
        let menuBar = toggle(Prefs.showMenuBarIcon, action: #selector(toggleMenuBar))
        let permission = NSButton(title: "打开设置", target: self, action: #selector(openAccessibility))
        permission.bezelStyle = .rounded
        let permsRow = makeRow(title: "辅助功能权限",
                               subtitle: Permissions.isTrusted ? "已授权，可以切换其他应用的窗口" : "未授权，只能列出窗口无法切换",
                               control: permission)
        let rows = [
            makeRow(title: "开机启动", subtitle: "登录时自动运行 hei", control: login),
            makeRow(title: "显示菜单栏图标", subtitle: "关闭后用快捷键仍然可以唤起", control: menuBar),
            permsRow,
        ]
        let bottom = card(rows: rows, width: width, top: top)
        return note("开机启动与菜单栏图标立即生效；辅助功能权限在系统设置中管理。", width: width, top: bottom)
    }

    private func buildAppearance(width: CGFloat, top: CGFloat) -> CGFloat {
        let follow = toggle(Prefs.followSystem, action: #selector(toggleFollow))
        var rows: [NSView] = [
            makeRow(title: "跟随系统外观", subtitle: "系统切换深色 / 浅色时自动适配", control: follow)
        ]

        if Prefs.followSystem {
            rows.append(makeRow(title: "深色主题", subtitle: nil,
                                control: popup(ThemeCatalog.all, selected: Prefs.darkTheme, action: #selector(changeDarkTheme))))
            rows.append(makeRow(title: "浅色主题", subtitle: nil,
                                control: popup(ThemeCatalog.all, selected: Prefs.lightTheme, action: #selector(changeLightTheme))))
        } else {
            rows.append(makeRow(title: "主题", subtitle: nil,
                                control: popup(ThemeCatalog.all, selected: Prefs.fixedTheme, action: #selector(changeFixedTheme))))
        }

        var bottom = card(rows: rows, width: width, top: top)
        bottom = note("主题决定面板的排版：启动器是单行 + 右侧 App 名，玻璃是双行 + 分隔线，极简更紧凑，经典是最初版本。", width: width, top: bottom)

        let preview = NSButton(title: "预览面板", target: self, action: #selector(previewPanel))
        preview.bezelStyle = .rounded
        bottom = card(rows: [makeRow(title: "预览", subtitle: "用示例数据打开一次切换面板", control: preview)],
                      width: width, top: bottom)
        return bottom
    }

    private func buildShortcuts(width: CGFloat, top: CGFloat) -> CGFloat {
        let combos: [(String, String)] = [
            ("cmd+shift+space", "⇧⌘Space"),
            ("opt+space", "⌥Space"),
            ("ctrl+opt+space", "⌃⌥Space"),
            ("cmd+shift+j", "⇧⌘J"),
        ]
        let current = UserDefaults.standard.string(forKey: "hotkey") ?? "cmd+shift+space"
        let row = makeRow(title: "唤起快捷键", subtitle: "修改后立即生效", control: popup(combos, selected: current, action: #selector(changeHotkey)))
        var bottom = card(rows: [row], width: width, top: top)
        bottom = note("不要使用 ⌘Tab（被 Dock 占用）或 ⌃Space（输入法切换）。", width: width, top: bottom)
        return bottom
    }

    private func buildAbout(width: CGFloat, top: CGFloat) -> CGFloat {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let log = NSButton(title: "打开日志", target: self, action: #selector(openLog))
        log.bezelStyle = .rounded
        let rows = [
            makeRow(title: "hei", subtitle: "嘿，窗口过来。", control: NSTextField(labelWithString: "v\(version)")),
            makeRow(title: "运行日志", subtitle: "~/Library/Logs/hei.log", control: log),
        ]
        return card(rows: rows, width: width, top: top)
    }

    // MARK: Actions

    @objc private func toggleLogin(_ sender: NSSwitch) {
        LaunchAtLogin.setEnabled(sender.state == .on)
        sender.state = LaunchAtLogin.isEnabled ? .on : .off
        reloadContent()
    }

    @objc private func toggleMenuBar(_ sender: NSSwitch) {
        Prefs.showMenuBarIcon = sender.state == .on
    }

    @objc private func toggleFollow(_ sender: NSSwitch) {
        Prefs.followSystem = sender.state == .on
        DispatchQueue.main.async {
            self.sidebarTable.reloadData()
            self.reloadContent()
        }
    }

    @objc private func changeDarkTheme(_ sender: NSPopUpButton) {
        Prefs.darkTheme = sender.selectedItem?.representedObject as? String ?? "launcher"
    }

    @objc private func changeLightTheme(_ sender: NSPopUpButton) {
        Prefs.lightTheme = sender.selectedItem?.representedObject as? String ?? "launcher"
    }

    @objc private func changeFixedTheme(_ sender: NSPopUpButton) {
        Prefs.fixedTheme = sender.selectedItem?.representedObject as? String ?? "launcher"
    }

    @objc private func changeHotkey(_ sender: NSPopUpButton) {
        let spec = sender.selectedItem?.representedObject as? String ?? "cmd+shift+space"
        UserDefaults.standard.set(spec, forKey: "hotkey")
        NotificationCenter.default.post(name: .heiPreferencesChanged, object: nil)
    }

    @objc private func openAccessibility() {
        Permissions.openAccessibilitySettings()
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/hei.log"))
    }

    @objc private func previewPanel() {
        (NSApp.delegate as? AppDelegate)?.previewSwitcher()
    }
}

// MARK: - Sidebar data

extension SettingsViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { sections.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = SidebarCell(width: sidebarWidth - 24)
        cell.configure(title: sections[row].title, icon: sections[row].icon,
                       highlighted: row == selectedSection)
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { true }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        SidebarRowView()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = sidebarTable.selectedRow
        guard row >= 0, row != selectedSection else { return }
        selectedSection = row
        sidebarTable.reloadData()
        reloadContent()
    }
}

final class SettingRow: FlippedView {
    let control: NSControl
    private let titleLabel: NSTextField
    private let subtitleLabel: NSTextField?
    private let height: CGFloat

    init(title: String, subtitle: String?, control: NSControl) {
        self.control = control
        self.height = subtitle == nil ? 44 : 56
        self.titleLabel = NSTextField(labelWithString: title)
        self.subtitleLabel = subtitle.map { NSTextField(labelWithString: $0) }
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: height))

        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        if let subtitleLabel {
            subtitleLabel.font = .systemFont(ofSize: 11)
            subtitleLabel.textColor = .secondaryLabelColor
            subtitleLabel.lineBreakMode = .byTruncatingTail
            addSubview(subtitleLabel)
        }
        control.sizeToFit()
        addSubview(control)
        layout(width: 600)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    func layout(width: CGFloat) {
        control.sizeToFit()
        var controlWidth = control.frame.width
        if control is NSPopUpButton { controlWidth = max(controlWidth, 112) }
        controlWidth = min(controlWidth, width * 0.46)
        control.frame.size.width = controlWidth
        control.frame.origin = NSPoint(x: width - 16 - controlWidth, y: ((height - control.frame.height) / 2).rounded())

        let textWidth = width - 32 - controlWidth - 16
        let titleHeight: CGFloat = 18
        if let subtitleLabel {
            let subtitleHeight: CGFloat = 15
            let block = titleHeight + 2 + subtitleHeight
            let top = ((height - block) / 2).rounded()
            titleLabel.frame = NSRect(x: 16, y: top, width: textWidth, height: titleHeight)
            subtitleLabel.frame = NSRect(x: 16, y: top + titleHeight + 2, width: textWidth, height: subtitleHeight)
        } else {
            titleLabel.frame = NSRect(x: 16, y: ((height - titleHeight) / 2).rounded(), width: textWidth, height: titleHeight)
        }
    }
}

private final class SidebarRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        let rect = bounds.insetBy(dx: 6, dy: 2)
        NSColor.labelColor.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
    }
}

private final class SidebarCell: NSTableCellView {
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var highlighted = false

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 34))
        iconView.frame = NSRect(x: 10, y: 9, width: 16, height: 16)
        iconView.contentTintColor = .secondaryLabelColor
        addSubview(iconView)

        label.font = .systemFont(ofSize: 13)
        label.frame = NSRect(x: 34, y: 8, width: width - 44, height: 18)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    func configure(title: String, icon: String, highlighted: Bool) {
        label.stringValue = title
        iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        self.highlighted = highlighted
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if highlighted {
            NSColor.labelColor.withAlphaComponent(0.11).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 2), xRadius: 7, yRadius: 7).fill()
        }
        super.draw(dirtyRect)
    }
}

// MARK: - Login item

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.write("login item \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
        }
    }
}
