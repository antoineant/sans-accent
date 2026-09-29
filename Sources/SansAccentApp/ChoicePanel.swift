import AppKit
import ApplicationServices

/// The small list of spellings shown above the word just typed.
/// It never takes focus: keys keep going to the app, and KeyboardTap drives the selection.
final class ChoicePanel {
    private let panel: NSPanel
    private let stack = NSStackView()
    private var rows: [NSTextField] = []
    private(set) var isVisible = false

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        panel.contentView = background
    }

    func show(_ options: [String], selected: Int) {
        rows.forEach { $0.removeFromSuperview() }
        rows = options.map { option in
            let row = NSTextField(labelWithString: " \(option) ")
            row.font = .systemFont(ofSize: 15)
            row.wantsLayer = true
            row.layer?.cornerRadius = 4
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
            return row
        }
        let hint = NSTextField(labelWithString: "↑↓  ⏎")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor
        rows.append(hint)
        stack.addArrangedSubview(hint)
        select(selected)

        panel.setContentSize(stack.fittingSize)
        position()
        panel.orderFrontRegardless()
        isVisible = true
    }

    func select(_ index: Int) {
        for (i, row) in rows.dropLast().enumerated() {
            let on = i == index
            row.layer?.backgroundColor = on ? NSColor.controlAccentColor.cgColor : nil
            row.textColor = on ? .white : .labelColor
        }
    }

    func hide() {
        guard isVisible else { return }
        panel.orderOut(nil)
        isVisible = false
    }

    // MARK: - Placement

    /// Just above the caret when the app reports it, else above the mouse pointer.
    private func position() {
        let size = panel.frame.size
        let anchor = Self.caretRect() ?? NSRect(origin: NSEvent.mouseLocation, size: .zero)
        let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero

        var origin = NSPoint(x: anchor.minX, y: anchor.maxY + 6)
        if origin.y + size.height > visible.maxY { origin.y = anchor.minY - size.height - 6 }  // no room above
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        panel.setFrameOrigin(origin)
    }

    /// Screen rect (Cocoa coordinates) of the character before the caret, via Accessibility.
    private static func caretRect() -> NSRect? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)  // never hang on a busy app

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID() else { return nil }
        let field = element as! AXUIElement

        var rangeValue: CFTypeRef?
        var range = CFRange()
        guard AXUIElementCopyAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue, AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else { return nil }

        var charRange = CFRange(location: max(range.location - 1, 0), length: range.location > 0 ? 1 : 0)
        guard let param = AXValueCreate(.cfRange, &charRange) else { return nil }
        var boundsValue: CFTypeRef?
        var rect = CGRect.zero
        guard AXUIElementCopyParameterizedAttributeValue(
                field, kAXBoundsForRangeParameterizedAttribute as CFString, param, &boundsValue) == .success,
              let boundsValue, AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect),
              rect.width > 0 || rect.height > 0 else { return nil }

        // Accessibility uses top-left origin on the primary screen; Cocoa uses bottom-left.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Chrome and Electron apps only expose text positions once asked to.
    static func enableAccessibility(for app: NSRunningApplication) {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }
}
