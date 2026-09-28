// Renders the app icon: "Sa" on a macOS-style rounded square.
// swift assets/make_icon.swift <style> <out.png> [size]   styles: blue, cream, tricolore, dark
import AppKit

let args = CommandLine.arguments
let style = args.count > 1 ? args[1] : "blue"
let out = args.count > 2 ? args[2] : "icon.png"
let size = args.count > 3 ? CGFloat(Double(args[3])!) : 1024

func font(_ design: NSFontDescriptor.SystemDesign, _ weight: NSFont.Weight, _ pt: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: pt, weight: weight)
    return NSFont(descriptor: base.fontDescriptor.withDesign(design) ?? base.fontDescriptor, size: pt) ?? base
}
func rgb(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

struct Style { let top: NSColor; let bottom: NSColor; let s: NSColor; let a: NSColor; let design: NSFontDescriptor.SystemDesign; let weight: NSFont.Weight }
let styles: [String: Style] = [
    "blue":      Style(top: rgb(0x3D6FE0), bottom: rgb(0x1B3A8A), s: .white, a: .white, design: .rounded, weight: .heavy),
    "cream":     Style(top: rgb(0xFBF7EF), bottom: rgb(0xEFE6D4), s: rgb(0x1C1C1E), a: rgb(0x1C1C1E), design: .serif, weight: .bold),
    "tricolore": Style(top: rgb(0xFFFFFF), bottom: rgb(0xECEEF3), s: rgb(0x1F3E9A), a: rgb(0xD62839), design: .rounded, weight: .heavy),
    "dark":      Style(top: rgb(0x2C2C30), bottom: rgb(0x151517), s: .white, a: rgb(0x5B8CFF), design: .default, weight: .bold),
]
let st = styles[style]!

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let k = size / 1024  // Apple's grid: 824pt square, 100pt margin, ~185pt corners

let rect = NSRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
let shape = NSBezierPath(roundedRect: rect, xRadius: 185 * k, yRadius: 185 * k)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.shadowBlurRadius = 20 * k
shadow.shadowOffset = NSSize(width: 0, height: -10 * k)
shadow.set()
st.bottom.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: st.top, ending: st.bottom)!.draw(in: shape, angle: -90)

let pt = 470 * k
let text = NSMutableAttributedString()
text.append(NSAttributedString(string: "S", attributes: [.font: font(st.design, st.weight, pt), .foregroundColor: st.s]))
text.append(NSAttributedString(string: "a", attributes: [.font: font(st.design, st.weight, pt), .foregroundColor: st.a, .kern: 0]))
let bounds = text.boundingRect(with: .zero, options: [.usesLineFragmentOrigin, .usesFontLeading])
let f = font(st.design, st.weight, pt)
// Center on the cap height, not the line box, so the letters sit optically in the middle.
text.draw(at: NSPoint(x: rect.midX - bounds.width / 2, y: rect.midY - f.capHeight / 2 + f.descender))

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
