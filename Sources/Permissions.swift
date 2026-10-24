import Cocoa
import ApplicationServices

enum Permissions {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestPrompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Clears this bundle id's Accessibility record. Needed because an ad-hoc signature's designated
    /// requirement is its cdhash: after a rebuild the old record still shows as "on" while matching nothing,
    /// and macOS never replaces it on its own.
    @discardableResult
    static func resetAccessibility() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "com.lvan.hei"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            Log.write("tccutil reset status=\(process.terminationStatus) output=\(output)")
            return process.terminationStatus == 0
        } catch {
            Log.write("tccutil reset failed: \(error.localizedDescription)")
            return false
        }
    }

    static func openAccessibilitySettings() {
        let raw = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: raw) {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Identifies the exact binary. Accessibility permission is pinned to the code signature, so a rebuild makes the
/// old TCC record stale while it still shows "on" in System Settings. Modification time + size changes on every
/// link, which is enough to detect "this is a different build".
enum BuildIdentity {
    static var id: String {
        guard let url = Bundle.main.executableURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return "unknown" }
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        return "\(Int(modified))-\(size)"
    }
}

enum Runtime {
    static let quiet = CommandLine.arguments.contains("--quiet")
    static let demo = CommandLine.arguments.contains("--demo")
    static let mock = CommandLine.arguments.contains("--mock")

    static let skipAutoReset = CommandLine.arguments.contains("--skip-auto-reset")
    static let alpha = CommandLine.arguments.contains("--alpha")
    static let dark = CommandLine.arguments.contains("--dark")

    static let theme: String = {
        guard let index = CommandLine.arguments.firstIndex(of: "--theme"),
              index + 1 < CommandLine.arguments.count else { return "launcher" }
        return CommandLine.arguments[index + 1]
    }()

    static let demoQuery: String? = {
        guard let index = CommandLine.arguments.firstIndex(of: "--query"),
              index + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[index + 1]
    }()
}
