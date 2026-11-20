// Draws the DMG window background: a heading, an arrow from the app to
// Applications, and the first-launch hint. Writes background.png and
// background@2x.png into the given folder; dmgbuild combines them for Retina.
//
//   swift scripts/dmg-background.swift <out-dir>
//
// The layout matches scripts/dmg-settings.py (640x400 window, icons centred
// at x 170 and 470, y 200).

import AppKit

let size = NSSize(width: 640, height: 400)
let iconY: CGFloat = 200
let appX: CGFloat = 170, applicationsX: CGFloat = 470

let blue = NSColor(srgbRed: 0.16, green: 0.42, blue: 0.93, alpha: 1)
let ink = NSColor(srgbRed: 0.11, green: 0.12, blue: 0.14, alpha: 1)
let muted = NSColor(srgbRed: 0.38, green: 0.40, blue: 0.44, alpha: 1)

func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, centreY: CGFloat) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: style,
    ]
    let height = (string as NSString).boundingRect(
        with: NSSize(width: 560, height: 200), options: .usesLineFragmentOrigin, attributes: attributes
    ).height
    (string as NSString).draw(
        with: NSRect(x: 40, y: centreY - height / 2, width: 560, height: height),
        options: .usesLineFragmentOrigin, attributes: attributes
    )
}

func draw() {
    // Flipped so y runs top-down like Finder's icon positions.
    NSGraphicsContext.current?.cgContext.translateBy(x: 0, y: size.height)
    NSGraphicsContext.current?.cgContext.scaleBy(x: 1, y: -1)
    let flipped = NSGraphicsContext(cgContext: NSGraphicsContext.current!.cgContext, flipped: true)
    NSGraphicsContext.current = flipped

    NSGradient(
        starting: NSColor(srgbRed: 0.97, green: 0.98, blue: 1.0, alpha: 1),
        ending: NSColor(srgbRed: 0.90, green: 0.93, blue: 0.98, alpha: 1)
    )!.draw(in: NSRect(origin: .zero, size: size), angle: 90)

    // Soft wells the two icons sit in.
    for x in [appX, applicationsX] {
        let well = NSBezierPath(roundedRect: NSRect(x: x - 86, y: iconY - 86, width: 172, height: 196), xRadius: 26, yRadius: 26)
        NSColor.white.withAlphaComponent(0.7).setFill()
        well.fill()
        NSColor(srgbRed: 0.16, green: 0.42, blue: 0.93, alpha: 0.10).setStroke()
        well.lineWidth = 1
        well.stroke()
    }

    text("Install AirBuds", size: 22, weight: .semibold, color: ink, centreY: 46)
    text("Drag AirBuds onto the Applications folder", size: 13, weight: .regular, color: muted, centreY: 76)

    // Arrow between the wells.
    let start = appX + 100, end = applicationsX - 100
    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: start, y: iconY))
    shaft.line(to: NSPoint(x: end - 6, y: iconY))
    shaft.lineWidth = 4
    shaft.lineCapStyle = .round
    blue.setStroke()
    shaft.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: end - 14, y: iconY - 10))
    head.line(to: NSPoint(x: end, y: iconY))
    head.line(to: NSPoint(x: end - 14, y: iconY + 10))
    head.lineWidth = 4
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    text(
        "First launch: macOS blocks apps that aren't notarized. Open System Settings ›\nPrivacy & Security and click Open Anyway, then allow Bluetooth when asked.",
        size: 11, weight: .regular, color: muted, centreY: 356
    )
}

func render(scale: CGFloat, to url: URL) throws {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = size // points, so the @2x file reports 144 dpi
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try render(scale: 1, to: out.appendingPathComponent("background.png"))
try render(scale: 2, to: out.appendingPathComponent("background@2x.png"))
