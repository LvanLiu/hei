import Cocoa
import Carbon.HIToolbox

struct KeyCombo {
    let keyCode: UInt32
    let modifiers: UInt32

    static let names: [String: UInt32] = [
        "a": UInt32(kVK_ANSI_A), "b": UInt32(kVK_ANSI_B), "c": UInt32(kVK_ANSI_C),
        "d": UInt32(kVK_ANSI_D), "e": UInt32(kVK_ANSI_E), "f": UInt32(kVK_ANSI_F),
        "g": UInt32(kVK_ANSI_G), "h": UInt32(kVK_ANSI_H), "i": UInt32(kVK_ANSI_I),
        "j": UInt32(kVK_ANSI_J), "k": UInt32(kVK_ANSI_K), "l": UInt32(kVK_ANSI_L),
        "m": UInt32(kVK_ANSI_M), "n": UInt32(kVK_ANSI_N), "o": UInt32(kVK_ANSI_O),
        "p": UInt32(kVK_ANSI_P), "q": UInt32(kVK_ANSI_Q), "r": UInt32(kVK_ANSI_R),
        "s": UInt32(kVK_ANSI_S), "t": UInt32(kVK_ANSI_T), "u": UInt32(kVK_ANSI_U),
        "v": UInt32(kVK_ANSI_V), "w": UInt32(kVK_ANSI_W), "x": UInt32(kVK_ANSI_X),
        "y": UInt32(kVK_ANSI_Y), "z": UInt32(kVK_ANSI_Z),
        "0": UInt32(kVK_ANSI_0), "1": UInt32(kVK_ANSI_1), "2": UInt32(kVK_ANSI_2),
        "3": UInt32(kVK_ANSI_3), "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5),
        "6": UInt32(kVK_ANSI_6), "7": UInt32(kVK_ANSI_7), "8": UInt32(kVK_ANSI_8),
        "9": UInt32(kVK_ANSI_9),
        "space": UInt32(kVK_Space), "tab": UInt32(kVK_Tab),
        "return": UInt32(kVK_Return), "escape": UInt32(kVK_Escape),
        "f1": UInt32(kVK_F1), "f2": UInt32(kVK_F2), "f3": UInt32(kVK_F3), "f4": UInt32(kVK_F4),
        "f5": UInt32(kVK_F5), "f6": UInt32(kVK_F6), "f7": UInt32(kVK_F7), "f8": UInt32(kVK_F8),
        "f9": UInt32(kVK_F9), "f10": UInt32(kVK_F10), "f11": UInt32(kVK_F11), "f12": UInt32(kVK_F12),
    ]

    var display: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        let name = KeyCombo.names.first { $0.value == keyCode }?.key ?? "?"
        return result + (name == "space" ? "Space" : name.capitalized)
    }

    static func parse(_ spec: String) -> KeyCombo? {
        var modifiers: UInt32 = 0
        var keyCode: UInt32?
        for raw in spec.lowercased().split(separator: "+") {
            let part = raw.trimmingCharacters(in: .whitespaces)
            switch part {
            case "cmd", "command", "⌘": modifiers |= UInt32(cmdKey)
            case "shift", "⇧": modifiers |= UInt32(shiftKey)
            case "opt", "option", "alt", "⌥": modifiers |= UInt32(optionKey)
            case "ctrl", "control", "⌃": modifiers |= UInt32(controlKey)
            default:
                guard let code = names[part] else { return nil }
                keyCode = code
            }
        }
        guard let keyCode else { return nil }
        return KeyCombo(keyCode: keyCode, modifiers: modifiers)
    }

    static var current: KeyCombo {
        let spec = UserDefaults.standard.string(forKey: "hotkey") ?? "cmd+shift+space"
        if let combo = parse(spec) { return combo }
        Log.write("invalid hotkey spec '\(spec)', falling back to cmd+shift+space")
        return parse("cmd+shift+space")!
    }
}

final class HotkeyManager {
    var onPress: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    @discardableResult
    func register(_ combo: KeyCombo) -> Bool {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, userData -> OSStatus in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { manager.onPress?() }
            return noErr
        }
        let installStatus = InstallEventHandler(GetEventDispatcherTarget(), callback, 1, &eventType,
                                                Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        guard installStatus == noErr else {
            Log.write("InstallEventHandler failed: \(installStatus)")
            return false
        }
        let hotKeyID = EventHotKeyID(signature: OSType(0x5746_4E44), id: 1)
        let registerStatus = RegisterEventHotKey(combo.keyCode, combo.modifiers, hotKeyID,
                                                 GetEventDispatcherTarget(), 0, &hotKeyRef)
        guard registerStatus == noErr else {
            Log.write("RegisterEventHotKey failed for \(combo.display): \(registerStatus)")
            return false
        }
        return true
    }
}
