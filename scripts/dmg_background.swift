import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let notarized = CommandLine.arguments.contains("--notarized")
let adHoc = CommandLine.arguments.contains("--ad-hoc")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let width: CGFloat = 840, height: CGFloat = 640
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
}
let ink = rgb(42, 30, 49), secondary = rgb(102, 92, 109), purple = rgb(123, 53, 163)

func text(_ value: String, x: CGFloat, y: CGFloat, w: CGFloat, size: CGFloat,
          weight: NSFont.Weight = .regular, color: NSColor = ink,
          alignment: NSTextAlignment = .left) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineSpacing = 3
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    (value as NSString).draw(in: NSRect(x: x, y: y, width: w, height: 80),
        withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
}

func render(scale: Int) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width) * scale,
        pixelsHigh: Int(height) * scale, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!
    // NSGraphicsContext uses the bitmap's point size to supply Retina scaling.
    context.cgContext.translateBy(x: 0, y: height)
    context.cgContext.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)

    NSGradient(starting: rgb(250, 248, 252), ending: rgb(235, 226, 242))!
        .draw(in: NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)), angle: 90)
    // A quiet silver header keeps the installer at home on a Mac.
    NSGradient(starting: rgb(254, 253, 255), ending: rgb(230, 224, 235))!
        .draw(in: NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: 112)), angle: 90)
    rgb(215, 204, 222).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 111, width: width, height: 1)).fill()
    text("Notch Monster", x: 0, y: 29, w: width, size: 31, weight: .bold, alignment: .center)
    text("Drag the hand to Applications.", x: 0, y: 73, w: width, size: 17, color: secondary, alignment: .center)

    // Finder draws the actual draggable app and Applications icons at (230,205)
    // and (610,205). Only the arrow and surrounding instructions are painted.
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 371, y: 205))
    arrow.line(to: NSPoint(x: 462, y: 205))
    arrow.lineWidth = 5; arrow.lineCapStyle = .round
    purple.withAlphaComponent(0.8).setStroke(); arrow.stroke()
    let tip = NSBezierPath()
    tip.move(to: NSPoint(x: 446, y: 190))
    tip.line(to: NSPoint(x: 462, y: 205))
    tip.line(to: NSPoint(x: 446, y: 220))
    tip.lineWidth = 5; tip.lineCapStyle = .round; tip.lineJoinStyle = .round; tip.stroke()
    text("Then open Notch Monster from Applications.", x: 40, y: 295, w: 760,
         size: 14, color: secondary, alignment: .center)

    let card = NSBezierPath(roundedRect: NSRect(x: 42, y: 343, width: 756, height: 210), xRadius: 14, yRadius: 14)
    NSColor.white.withAlphaComponent(0.8).setFill(); card.fill()
    rgb(212, 199, 221).setStroke(); card.lineWidth = 1; card.stroke()
    if notarized {
        text("Make yourself at home", x: 66, y: 365, w: 708, size: 17, weight: .semibold)
        text("1. Open Notch Monster from Applications.", x: 66, y: 405, w: 708, size: 14)
        text("2. Allow Accessibility and Screen Recording when asked.", x: 66, y: 438, w: 708, size: 14)
        text("3. Drag a spare file or window toward your notch.", x: 66, y: 471, w: 708, size: 14)
    } else {
        text("One extra step for this early build", x: 66, y: 363, w: 708, size: 17, weight: .semibold)
        text(adHoc ? "This interim build has an ad hoc signature and is not notarized by Apple."
             : "This app isn’t notarized by Apple, so macOS will show a warning.",
             x: 66, y: 395, w: 708, size: 13, color: secondary)
        text("1. Open the app once, then dismiss the warning.", x: 66, y: 430, w: 708, size: 14)
        text("2. System Settings → Privacy & Security → Open Anyway.", x: 66, y: 461, w: 708, size: 14, weight: .medium)
        text("3. Authenticate and confirm Open.", x: 66, y: 492, w: 708, size: 14)
    }
    text("Allow Accessibility and Screen Recording. Click the Dock icon to reopen Settings.",
         x: 36, y: 568, w: 768, size: 12, color: secondary, alignment: .center)
    if adHoc {
        text("After an update, you may need to remove and re-add the app in both permission lists.",
             x: 36, y: 589, w: 768, size: 11, color: secondary, alignment: .center)
    }
    text("macOS 15+  ·  Apple silicon  ·  Files go to Trash. Windows get closed.",
         x: 40, y: 612, w: 760, size: 11, color: secondary, alignment: .center)
    let name = scale == 1 ? "installer.png" : "installer@2x.png"
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
}
try render(scale: 1)
try render(scale: 2)
