import Cocoa

let arguments = CommandLine.arguments
if arguments.contains("--selftest") {
    exit(SelfTest.run() ? 0 : 1)
}
if arguments.contains("--build-id") {
    print(BuildIdentity.id)
    exit(0)
}
if arguments.contains("--reset-tcc") {
    exit(Permissions.resetAccessibility() ? 0 : 1)
}
if arguments.contains("--dump") {
    exit(SelfTest.dump() ? 0 : 1)
}

let application = NSApplication.shared
Theme.current = Theme.named(Runtime.theme)
if Runtime.dark {
    application.appearance = NSAppearance(named: .darkAqua)
}
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.accessory)
application.run()
