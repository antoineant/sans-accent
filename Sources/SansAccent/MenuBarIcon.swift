import AppKit

/// The menu bar logo: "Sa" cut out of a small rounded square, echoing the app icon.
/// A template image, so macOS tints it for light/dark menu bars like its neighbours.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 20, height: 16), flipped: false) { rect in
            draw(in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }()

    static func draw(in rect: NSRect) {
        let k = rect.height / 16
        NSColor.black.setFill()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5 * k, dy: 0.5 * k), xRadius: 4 * k, yRadius: 4 * k).fill()

        let base = NSFont.systemFont(ofSize: 11 * k, weight: .heavy)
        let font = NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: 11 * k) ?? base
        let text = NSAttributedString(string: "Sa", attributes: [.font: font, .foregroundColor: NSColor.black])
        // Letters punched through the square: they take the menu bar's own color.
        NSGraphicsContext.current?.cgContext.setBlendMode(.destinationOut)
        let width = text.size().width
        text.draw(at: NSPoint(x: rect.midX - width / 2, y: rect.midY - font.capHeight / 2 + font.descender))
        NSGraphicsContext.current?.cgContext.setBlendMode(.normal)
    }
}
