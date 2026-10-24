import Cocoa
import ApplicationServices
import Darwin

enum Flipper {
    static func focus(_ item: WindowItem) {
        if item.isMinimized {
            AXUIElementSetAttributeValue(item.ax, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        if let wid = item.wid, wid != 0, SpaceFocus.follow(pid: item.pid, windowID: wid) {
            AXUIElementPerformAction(item.ax, kAXRaiseAction as CFString)
            return
        }
        focusHere(item)
    }

    /// `activate` has been advisory since macOS 14 and will not follow a window onto another Space.
    private static func focusHere(_ item: WindowItem) {
        guard let app = NSRunningApplication(processIdentifier: item.pid) else { return }
        AXUIElementPerformAction(item.ax, kAXRaiseAction as CFString)
        app.activate(options: [.activateAllWindows])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            AXUIElementPerformAction(item.ax, kAXRaiseAction as CFString)
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != item.pid {
                app.activate(options: [.activateAllWindows])
            }
        }
    }
}

/// Raises a window by id so the window server follows it onto its Space.
/// A later `activate` would pull focus back to the Space the switcher was opened on.
enum SpaceFocus {
    static var symbolsLoaded: Bool { symbols != nil }

    static func follow(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard let symbols else {
            Log.write("space focus symbols unavailable")
            return false
        }
        var psn = ProcessSerialNumber()
        return withUnsafeMutablePointer(to: &psn) { pointer in
            let raw = UnsafeMutableRawPointer(pointer)
            guard symbols.processForPID(pid, raw) == 0 else {
                Log.write("space focus: no process serial for pid \(pid)")
                return false
            }
            let status = symbols.setFront(raw, windowID, userGenerated)
            guard status == 0 else {
                Log.write("space focus: set front failed (\(status)) wid=\(windowID)")
                return false
            }
            for type in [KeyClick.down, KeyClick.up] {
                var record = eventRecord(type: type, windowID: windowID)
                record.withUnsafeMutableBytes { bytes in
                    guard let base = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                    _ = symbols.postEvent(raw, base)
                }
            }
            return true
        }
    }

    /// Synthetic mouse-down / mouse-up so the target app accepts the new key window.
    /// `CGSEncodeEventRecord` reads 8 bytes past the 0xF8 length, so the buffer is 0x100 and zeroed.
    static func eventRecord(type: UInt8, windowID: CGWindowID) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: KeyClick.byteCount)
        bytes[KeyClick.lengthOffset] = KeyClick.recordLength
        bytes[KeyClick.typeOffset] = type
        bytes[KeyClick.connectionOffset] = KeyClick.connection
        var wid = windowID
        withUnsafeBytes(of: &wid) { raw in
            for (offset, byte) in raw.enumerated() {
                bytes[KeyClick.windowOffset + offset] = byte
            }
        }
        for offset in 0..<KeyClick.flagCount {
            bytes[KeyClick.flagsOffset + offset] = 0xFF
        }
        return bytes
    }

    private static let userGenerated: UInt32 = 0x200
    private static let symbols: FrontSymbols? = FrontSymbols.load()
}

private enum KeyClick {
    static let byteCount = 0x100
    static let recordLength: UInt8 = 0xF8
    static let lengthOffset = 0x04
    static let typeOffset = 0x08
    static let flagsOffset = 0x20
    static let flagCount = 0x10
    static let connectionOffset = 0x3A
    static let connection: UInt8 = 0x10
    static let windowOffset = 0x3C
    static let down: UInt8 = 0x01
    static let up: UInt8 = 0x02
}

private struct ProcessSerialNumber {
    var highLongOfPSN: UInt32 = 0
    var lowLongOfPSN: UInt32 = 0
}

private struct FrontSymbols {
    let processForPID: @convention(c) (pid_t, UnsafeMutableRawPointer) -> Int32
    let setFront: @convention(c) (UnsafeMutableRawPointer, UInt32, UInt32) -> Int32
    let postEvent: @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt8>) -> Int32

    static func load() -> FrontSymbols? {
        guard MemoryLayout<ProcessSerialNumber>.size == 8,
              let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let hiServices = dlopen("/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices", RTLD_LAZY),
              let processSymbol = dlsym(hiServices, "GetProcessForPID"),
              let frontSymbol = dlsym(skyLight, "_SLPSSetFrontProcessWithOptions"),
              let postSymbol = dlsym(skyLight, "SLPSPostEventRecordTo") else {
            return nil
        }
        return FrontSymbols(
            processForPID: unsafeBitCast(processSymbol, to: ProcessFn.self),
            setFront: unsafeBitCast(frontSymbol, to: FrontFn.self),
            postEvent: unsafeBitCast(postSymbol, to: PostFn.self)
        )
    }

    private typealias ProcessFn = @convention(c) (pid_t, UnsafeMutableRawPointer) -> Int32
    private typealias FrontFn = @convention(c) (UnsafeMutableRawPointer, UInt32, UInt32) -> Int32
    private typealias PostFn = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt8>) -> Int32
}
