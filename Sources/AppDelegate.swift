import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var switcher: SwitcherController!
    private var hotkey: HotkeyManager!
    private var statusItem: NSStatusItem?
    private lazy var settingsWindow = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("launch pid=\(getpid()) ppid=\(getppid()) trusted=\(Permissions.isTrusted) hotkey=\(KeyCombo.current.display) demo=\(Runtime.demo) mock=\(Runtime.mock)")
        // An ad-hoc rebuild gets a new cdhash, so the previous build's TCC record still reads "on" while
        // matching nothing. Detect a build change and clear the stale record once, automatically.
        let buildKey = "trustedBuildHash"
        let currentHash = BuildIdentity.id
        if !Permissions.isTrusted && !Runtime.demo && !Runtime.skipAutoReset,
           UserDefaults.standard.string(forKey: buildKey) != currentHash {
            UserDefaults.standard.set(currentHash, forKey: buildKey)
            Log.write("new build \(currentHash): clearing stale TCC record")
            _ = Permissions.resetAccessibility()
        }

        AppUsage.shared.start()

        switcher = SwitcherController()
        hotkey = HotkeyManager()
        hotkey.onPress = { [weak self] in self?.switcher.toggle() }
        if hotkey.register(KeyCombo.current) {
            Log.write("hotkey registered: \(KeyCombo.current.display)")
        } else {
            Log.write("hotkey registration failed: \(KeyCombo.current.display)")
        }
        installStatusItem()
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged),
                                               name: .heiPreferencesChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(openSettingsFromSwitcher(_:)),
                                               name: .heiOpenSettings, object: nil)

        // Without this, a double-click only puts an icon in the menu bar (often clipped by the notch on a
        // crowded bar), which reads as "nothing happened". While untrusted, surface the permission flow.
        if !Runtime.demo && !Permissions.isTrusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.switcher.show()
            }
        }

        if let index = CommandLine.arguments.firstIndex(of: "--settings-snapshot"),
           index + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.settingsWindow.present()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    self?.settingsWindow.snapshot(to: path)
                }
            }
        }

        if Runtime.demo {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.switcher.show()
            }
            if let index = CommandLine.arguments.firstIndex(of: "--snapshot"),
               index + 1 < CommandLine.arguments.count {
                let path = CommandLine.arguments[index + 1]
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                    self?.switcher.snapshot(to: path)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle",
                                     accessibilityDescription: "hei")
        item.button?.toolTip = "hei"

        let menu = NSMenu()
        let show = NSMenuItem(title: "显示窗口切换器", action: #selector(showSwitcher), keyEquivalent: "")
        show.target = self
        menu.addItem(show)

        let hotkeyItem = NSMenuItem(title: "快捷键：\(KeyCombo.current.display)", action: nil, keyEquivalent: "")
        hotkeyItem.isEnabled = false
        menu.addItem(hotkeyItem)

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let permissions = NSMenuItem(title: "辅助功能权限…", action: #selector(openPermissions), keyEquivalent: "")
        permissions.target = self
        menu.addItem(permissions)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 hei", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
        item.isVisible = Prefs.showMenuBarIcon
    }

    private func rebuildMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()
        let show = NSMenuItem(title: "显示窗口切换器", action: #selector(showSwitcher), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        let hotkeyItem = NSMenuItem(title: "快捷键：\(KeyCombo.current.display)", action: nil, keyEquivalent: "")
        hotkeyItem.isEnabled = false
        menu.addItem(hotkeyItem)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let permissions = NSMenuItem(title: "辅助功能权限…", action: #selector(openPermissions), keyEquivalent: "")
        permissions.target = self
        menu.addItem(permissions)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 hei", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
    }

    @objc func previewSwitcher() {
        switcher.show()
    }

    @objc private func openSettings() {
        settingsWindow.present()
    }

    @objc private func openSettingsFromSwitcher(_ notification: Notification) {
        openSettings()
    }

    @objc private func preferencesChanged() {
        hotkey.register(KeyCombo.current)
        statusItem?.isVisible = Prefs.showMenuBarIcon
        rebuildMenu()
        switcher.applyPreferences()
    }

    @objc private func showSwitcher() {
        switcher.show()
    }

    @objc private func openPermissions() {
        Permissions.openAccessibilitySettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
