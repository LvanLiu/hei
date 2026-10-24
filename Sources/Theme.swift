import Cocoa

/// Visual parameters for the switcher panel. Every metric the controller and the cells need lives here so a
/// theme is one struct, not a set of scattered constants.
struct Theme {
    let id: String
    let width: CGFloat
    let rowHeight: CGFloat
    let searchHeight: CGFloat
    let footerHeight: CGFloat
    let cornerRadius: CGFloat
    let iconSize: CGFloat
    let iconLeading: CGFloat
    let titleSize: CGFloat
    let titleWeight: NSFont.Weight
    let subtitleSize: CGFloat
    let searchSize: CGFloat
    let selectionFill: CGFloat
    let selectionBar: Bool
    let selectionInset: CGFloat
    let selectionRadius: CGFloat
    let divider: Bool
    let keycaps: Bool
    let showCount: Bool
    let material: NSVisualEffectView.Material
    let singleLine: Bool
    let metaColumn: Bool
    let sectionHeader: Bool
    let footerPill: Bool
    let neutralSelection: Bool

    init(id: String, width: CGFloat, rowHeight: CGFloat, searchHeight: CGFloat, footerHeight: CGFloat,
         cornerRadius: CGFloat, iconSize: CGFloat, iconLeading: CGFloat, titleSize: CGFloat,
         titleWeight: NSFont.Weight, subtitleSize: CGFloat, searchSize: CGFloat, selectionFill: CGFloat,
         selectionBar: Bool, selectionInset: CGFloat, selectionRadius: CGFloat, divider: Bool,
         keycaps: Bool, showCount: Bool, material: NSVisualEffectView.Material,
         singleLine: Bool = false, metaColumn: Bool = false, sectionHeader: Bool = false,
         footerPill: Bool = false, neutralSelection: Bool = false) {
        self.id = id
        self.width = width
        self.rowHeight = rowHeight
        self.searchHeight = searchHeight
        self.footerHeight = footerHeight
        self.cornerRadius = cornerRadius
        self.iconSize = iconSize
        self.iconLeading = iconLeading
        self.titleSize = titleSize
        self.titleWeight = titleWeight
        self.subtitleSize = subtitleSize
        self.searchSize = searchSize
        self.selectionFill = selectionFill
        self.selectionBar = selectionBar
        self.selectionInset = selectionInset
        self.selectionRadius = selectionRadius
        self.divider = divider
        self.keycaps = keycaps
        self.showCount = showCount
        self.material = material
        self.singleLine = singleLine
        self.metaColumn = metaColumn
        self.sectionHeader = sectionHeader
        self.footerPill = footerPill
        self.neutralSelection = neutralSelection
    }

    var titleFont: NSFont { .systemFont(ofSize: titleSize, weight: titleWeight) }
    var subtitleFont: NSFont { .systemFont(ofSize: subtitleSize) }
    var searchFont: NSFont { .systemFont(ofSize: searchSize) }
    var textLeading: CGFloat { iconLeading + iconSize + 12 }

    static let classic = Theme(
        id: "classic", width: 640, rowHeight: 46, searchHeight: 54, footerHeight: 26,
        cornerRadius: 14, iconSize: 22, iconLeading: 16, titleSize: 13, titleWeight: .regular,
        subtitleSize: 11, searchSize: 15, selectionFill: 0.22, selectionBar: false,
        selectionInset: 6, selectionRadius: 8, divider: false, keycaps: false, showCount: false,
        material: .popover)

    static let glass = Theme(
        id: "glass", width: 620, rowHeight: 52, searchHeight: 62, footerHeight: 32,
        cornerRadius: 18, iconSize: 26, iconLeading: 20, titleSize: 14, titleWeight: .medium,
        subtitleSize: 11.5, searchSize: 17, selectionFill: 0.18, selectionBar: false,
        selectionInset: 8, selectionRadius: 12, divider: true, keycaps: true, showCount: true,
        material: .hudWindow)

    static let minimal = Theme(
        id: "minimal", width: 600, rowHeight: 44, searchHeight: 52, footerHeight: 26,
        cornerRadius: 12, iconSize: 20, iconLeading: 20, titleSize: 13.5, titleWeight: .regular,
        subtitleSize: 10.5, searchSize: 16, selectionFill: 0.10, selectionBar: true,
        selectionInset: 4, selectionRadius: 6, divider: false, keycaps: true, showCount: false,
        material: .menu)

    /// Launcher layout: large search line, one-line rows with a right-aligned app column,
    /// a section header, and a pill footer. Modelled on Raycast's information hierarchy.
    static let launcher = Theme(
        id: "launcher", width: 720, rowHeight: 56, searchHeight: 88, footerHeight: 64,
        cornerRadius: 24, iconSize: 28, iconLeading: 24, titleSize: 15, titleWeight: .regular,
        subtitleSize: 13, searchSize: 22, selectionFill: 0.09, selectionBar: false,
        selectionInset: 12, selectionRadius: 12, divider: false, keycaps: true, showCount: false,
        material: .popover, singleLine: true, metaColumn: true, sectionHeader: true,
        footerPill: true, neutralSelection: true)

    static var current: Theme = .launcher

    static func named(_ id: String) -> Theme {
        switch id {
        case "glass": return .glass
        case "minimal": return .minimal
        case "launcher": return .launcher
        default: return .classic
        }
    }
}

/// Footer: optional window count on the left, keyboard hints on the right. In `footerPill` mode it draws a
/// capsule holding a leading action and trailing hints.
final class HintBar: NSView {
    var theme: Theme = .current
    var leftText: String = ""
    var items: [(String, String)] = [("↑↓", "选择"), ("↩", "切换"), ("esc", "取消")]

    private let labelFont = NSFont.systemFont(ofSize: 11)
    private let pillLabelFont = NSFont.systemFont(ofSize: 12)
    private let keyFont = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .medium)

    override func draw(_ dirtyRect: NSRect) {
        theme.footerPill ? drawPill() : drawPlain()
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    private func drawPill() {
        let pill = NSRect(x: 16, y: 11, width: bounds.width - 32, height: bounds.height - 22)
        let path = NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2)
        NSColor.labelColor.withAlphaComponent(0.07).setFill()
        path.fill()
        NSColor.labelColor.withAlphaComponent(0.12).setStroke()
        path.lineWidth = 1
        path.stroke()

        _ = drawKey("↩", "切换", left: pill.minX + 18, centerY: pill.midY, font: pillLabelFont,
                    labelColor: .secondaryLabelColor)
        var right = pill.maxX - 18
        for (key, label) in [("esc", "取消"), ("↑↓", "选择")] {
            right = drawKey(key, label, right: right, centerY: pill.midY, font: pillLabelFont)
        }
    }

    private func drawPlain() {
        if !leftText.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: NSColor.tertiaryLabelColor]
            let size = (leftText as NSString).size(withAttributes: attributes)
            (leftText as NSString).draw(at: NSPoint(x: theme.iconLeading, y: (bounds.height - size.height) / 2),
                                        withAttributes: attributes)
        }

        guard theme.keycaps else {
            let text = items.map { "\($0.0) \($0.1)" }.joined(separator: "    ")
            let attributes: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: NSColor.tertiaryLabelColor]
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(at: NSPoint(x: bounds.width - size.width - theme.iconLeading,
                                                y: (bounds.height - size.height) / 2),
                                    withAttributes: attributes)
            return
        }

        var right = bounds.width - theme.iconLeading
        for (key, label) in items.reversed() {
            right = drawKey(key, label, right: right, centerY: bounds.midY, font: labelFont)
        }
    }

    @discardableResult
    private func drawKey(_ key: String, _ label: String, left: CGFloat = 0, right: CGFloat = 0,
                         centerY: CGFloat, font: NSFont,
                         labelColor: NSColor = .tertiaryLabelColor) -> CGFloat {
        let labelAttributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: labelColor]
        let labelSize = (label as NSString).size(withAttributes: labelAttributes)
        let keyAttributes: [NSAttributedString.Key: Any] = [.font: keyFont, .foregroundColor: NSColor.secondaryLabelColor]
        let keySize = (key as NSString).size(withAttributes: keyAttributes)
        let capWidth = keySize.width + 11
        let capHeight: CGFloat = 18

        let capX: CGFloat
        let labelX: CGFloat
        if right > 0 {
            labelX = right - labelSize.width
            capX = labelX - 7 - capWidth
        } else {
            capX = left
            labelX = capX + capWidth + 7
        }

        let cap = NSRect(x: capX, y: centerY - capHeight / 2, width: capWidth, height: capHeight)
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        NSBezierPath(roundedRect: cap, xRadius: 4.5, yRadius: 4.5).fill()
        NSColor.labelColor.withAlphaComponent(0.10).setStroke()
        let stroke = NSBezierPath(roundedRect: cap.insetBy(dx: 0.5, dy: 0.5), xRadius: 4.5, yRadius: 4.5)
        stroke.lineWidth = 1
        stroke.stroke()
        (key as NSString).draw(at: NSPoint(x: cap.minX + 5.5, y: cap.midY - keySize.height / 2),
                               withAttributes: keyAttributes)
        (label as NSString).draw(at: NSPoint(x: labelX, y: centerY - labelSize.height / 2),
                                 withAttributes: labelAttributes)

        return right > 0 ? capX - 16 : labelX + labelSize.width + 16
    }
}
