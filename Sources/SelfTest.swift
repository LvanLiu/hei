import Cocoa

enum SelfTest {
    static func run() -> Bool {
        var failures: [String] = []
        var total = 0

        func check(_ name: String, _ condition: Bool) {
            total += 1
            print("\(condition ? "PASS" : "FAIL")  \(name)")
            if !condition { failures.append(name) }
        }

        func score(_ query: String, _ app: String, _ title: String) -> Int? {
            Matcher.match(query: query, app: app, title: title)?.score
        }

        check("empty query matches everything",
              Matcher.match(query: "", app: "Safari", title: "Apple")?.score == 0)

        check("app prefix match",
              score("chr", "Google Chrome", "New Tab") != nil)

        check("title prefix beats word prefix",
              (score("chr", "Ghostty", "my chrome notes") ?? 0) < (score("chr", "Ghostty", "chrome") ?? 0))

        check("acronym match",
              score("gc", "Google Chrome", "New Tab") != nil)

        check("word prefix match",
              (score("code", "Code", "Visual Studio Code") ?? 0) >= 700)

        check("subsequence match",
              score("smf", "Xcode", "src/main.swift") != nil)

        check("no match returns nil",
              Matcher.match(query: "qqzz", app: "Safari", title: "apple.com") == nil)

        if let match = Matcher.match(query: "文档", app: "Finder", title: "项目文档.md") {
            check("chinese title match", !match.titleSpans.isEmpty)
            check("chinese span is correct", match.titleSpans.first == 2..<4)
        } else {
            check("chinese title match", false)
        }

        if let match = Matcher.match(query: "cafe", app: "Finder", title: "Café") {
            check("diacritic insensitive", match.titleSpans.first == 0..<4)
        } else {
            check("diacritic insensitive", false)
        }

        if let match = Matcher.match(query: "main", app: "Xcode", title: "main.swift — hei") {
            check("title spans highlight the query", match.titleSpans.first == 0..<4)
        } else {
            check("title spans highlight the query", false)
        }

        check("settings is an exact command",
              SwitcherCommand.settings.isExact("settings"))
        check("设置 is an exact command",
              SwitcherCommand.settings.isExact("设置"))
        check("a single letter is not an exact command",
              !SwitcherCommand.settings.isExact("s"))
        check("unrelated text does not match the settings command",
              SwitcherCommand.settings.match(query: "qqzz") == nil)
        check("settings outranks a fuzzy window title",
              (SwitcherCommand.settings.match(query: "settings")?.score ?? 0) >
                (Matcher.match(query: "settings", app: "Safari", title: "SessionService.java")?.score ?? 0))

        let down = SpaceFocus.eventRecord(type: 0x01, windowID: 7)
        let up = SpaceFocus.eventRecord(type: 0x02, windowID: 7)
        check("space focus symbols load", SpaceFocus.symbolsLoaded)
        check("key event record is zero-padded past the encoded length",
              down.count == 0x100 && down[0xF8] == 0 && down[0xFF] == 0)
        check("key event record carries the window id",
              down[0x04] == 0xF8 && down[0x08] == 0x01 && down[0x3A] == 0x10 &&
                down[0x3C] == 7 && down[0x3D] == 0 && down[0x20] == 0xFF && down[0x2F] == 0xFF)
        check("key up record uses the mouse-up type", up[0x08] == 0x02)

        print("")
        print("accessibility trusted: \(Permissions.isTrusted)")

        if failures.isEmpty {
            print("all \(total) checks passed")
            return true
        }
        print("\(failures.count) check(s) failed: \(failures.joined(separator: ", "))")
        return false
    }

    static func dump() -> Bool {
        guard Permissions.isTrusted else {
            print("accessibility permission not granted; cannot enumerate windows")
            return false
        }
        var scanned: [WindowItem] = []
        let semaphore = DispatchSemaphore(value: 0)
        WindowScanner.shared.scan(completionQueue: .global()) { items in
            scanned = items
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5)
        for item in scanned {
            print("pid=\(item.pid) wid=\(item.wid.map(String.init) ?? "-") z=\(item.zOrder) min=\(item.isMinimized) app=\(item.appName) | \(item.title)")
        }
        print("\(scanned.count) window(s)")
        return !scanned.isEmpty
    }
}
