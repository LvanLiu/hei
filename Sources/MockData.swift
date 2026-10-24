import Cocoa
import ApplicationServices

/// Fixture windows for `--mock`, so the UI can be inspected without Accessibility permission.
enum MockData {
    static let items: [WindowItem] = [
        make("Safari", "Apple Developer Documentation"),
        make("Google Chrome", "Window switcher for macOS — Google Search"),
        make("Xcode", "hei — SwitcherPanel.swift"),
        make("Xcode", "hei — Matcher.swift"),
        make("Ghostty", "~/default-workspace/hei"),
        make("Notes", "调研笔记：macOS 窗口切换"),
        make("Finder", "项目文档"),
        make("Music", "正在播放：Nightwalk"),
    ]

    private static func make(_ app: String, _ title: String) -> WindowItem {
        WindowItem(pid: 0,
                   ax: AXUIElementCreateSystemWide(),
                   appName: app,
                   title: title,
                   isMinimized: false,
                   zOrder: 0,
                   wid: nil)
    }
}
