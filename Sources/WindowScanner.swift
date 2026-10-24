import Cocoa
import ApplicationServices
import Darwin

struct WindowItem {
    let pid: pid_t
    let ax: AXUIElement
    let appName: String
    let title: String
    let isMinimized: Bool
    let zOrder: Int
    let wid: CGWindowID?

    var key: String { "\(pid)-\(wid.map(String.init) ?? title)" }
}

/// Enumerates every standard window of every regular app via the Accessibility API.
/// Calls are per-app, concurrent, and time-boxed: one unresponsive app must never stall the switcher.
final class WindowScanner {
    static let shared = WindowScanner()

    private let queue = DispatchQueue(label: "wf.scan", qos: .userInitiated, attributes: .concurrent)
    private static let allowedSubroles: Set<String> = ["AXStandardWindow", "AXDialog", "AXFloatingWindow", "AXSystemDialog"]

    private static let axGetWindow: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError)? = {
        guard let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY),
              let symbol = dlsym(handle, "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError).self)
    }()

    func scan(timeout: TimeInterval = 1.2,
              completionQueue: DispatchQueue = .main,
              completion: @escaping ([WindowItem]) -> Void) {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != getpid()
        }
        let zOrder = Self.onScreenZOrder()
        let lock = NSLock()
        var collected: [WindowItem] = []
        let group = DispatchGroup()

        for app in apps {
            group.enter()
            queue.async {
                let found = Self.windows(for: app, zOrder: zOrder)
                lock.lock()
                collected.append(contentsOf: found)
                lock.unlock()
                group.leave()
            }
        }

        let deliver = {
            lock.lock()
            let snapshot = collected
            lock.unlock()
            let sorted = Self.sorted(snapshot)
            completionQueue.async { completion(sorted) }
        }

        group.notify(queue: .global(qos: .userInitiated), execute: deliver)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout, execute: deliver)
    }

    private static func attrs(_ element: AXUIElement, _ names: [String]) -> [String: CFTypeRef] {
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, names as CFArray, [], &values) == .success,
              let array = values as? [CFTypeRef] else {
            return names.reduce(into: [:]) { result, name in
                if let value = attr(element, name) { result[name] = value }
            }
        }
        var result: [String: CFTypeRef] = [:]
        for (index, name) in names.enumerated() where index < array.count {
            let value = array[index]
            if CFGetTypeID(value) != CFNullGetTypeID() { result[name] = value }
        }
        return result
    }

    private static func attr(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func windows(for app: NSRunningApplication, zOrder: [CGWindowID: Int]) -> [WindowItem] {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.25)

        guard let raw = attr(appElement, kAXWindowsAttribute) as? [AXUIElement] else { return [] }
        let appName = app.localizedName ?? "Unknown"

        var result: [WindowItem] = []
        for element in raw {
            let values = attrs(element, [kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute,
                                        kAXMinimizedAttribute, kAXSizeAttribute])
            guard let role = values[kAXRoleAttribute] as? String, role == kAXWindowRole else { continue }
            if let subrole = values[kAXSubroleAttribute] as? String, !allowedSubroles.contains(subrole) { continue }
            if let size = size(from: values[kAXSizeAttribute]), size.width < 60 || size.height < 40 { continue }

            let title = ((values[kAXTitleAttribute] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let minimized = (values[kAXMinimizedAttribute] as? NSNumber)?.boolValue ?? false
            let wid = windowID(of: element)
            let z = wid.flatMap { zOrder[$0] } ?? 10_000

            result.append(WindowItem(pid: app.processIdentifier,
                                     ax: element,
                                     appName: appName,
                                     title: title.isEmpty ? appName : title,
                                     isMinimized: minimized,
                                     zOrder: z,
                                     wid: wid))
        }
        return result
    }

    private static func size(from value: CFTypeRef?) -> CGSize? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    private static func windowID(of element: AXUIElement) -> CGWindowID? {
        guard let axGetWindow else { return nil }
        var wid: CGWindowID = 0
        guard axGetWindow(element, &wid) == .success, wid != 0 else { return nil }
        return wid
    }

    private static func onScreenZOrder() -> [CGWindowID: Int] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [:] }
        var map: [CGWindowID: Int] = [:]
        for (index, info) in list.enumerated() {
            if let number = info[kCGWindowNumber as String] as? Int {
                map[CGWindowID(number)] = index
            }
        }
        return map
    }

    private static func sorted(_ items: [WindowItem]) -> [WindowItem] {
        items.sorted { a, b in
            let rankA = AppUsage.shared.index(of: a.pid) ?? 999
            let rankB = AppUsage.shared.index(of: b.pid) ?? 999
            if rankA != rankB { return rankA < rankB }
            if a.zOrder != b.zOrder { return a.zOrder < b.zOrder }
            if a.appName != b.appName {
                return a.appName.localizedStandardCompare(b.appName) == .orderedAscending
            }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }
}
