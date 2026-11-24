// Draws the fm-object-clip app icon (1024 x 1024 PNG) with AppKit.
// Usage: swift scripts/make-icon.swift OUT.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

// Background: a rounded square on the macOS icon grid, blue to teal.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = rgb(0, 0, 0, 0.30)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
rgb(40, 100, 230).setFill()
tilePath.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: rgb(52, 120, 246), ending: rgb(20, 184, 196))!.draw(in: tilePath, angle: -60)

// Clipboard board.
let board = NSRect(x: 292, y: 210, width: 440, height: 560)
NSGraphicsContext.saveGraphicsState()
let s2 = NSShadow()
s2.shadowColor = rgb(0, 0, 0, 0.25)
s2.shadowBlurRadius = 18
s2.shadowOffset = NSSize(width: 0, height: -8)
s2.set()
rgb(255, 255, 255).setFill()
NSBezierPath(roundedRect: board, xRadius: 48, yRadius: 48).fill()
NSGraphicsContext.restoreGraphicsState()

// Clip at the top.
rgb(30, 50, 90).setFill()
NSBezierPath(roundedRect: NSRect(x: 412, y: 722, width: 200, height: 92), xRadius: 30, yRadius: 30).fill()
rgb(255, 255, 255).setFill()
NSBezierPath(ovalIn: NSRect(x: 492, y: 772, width: 40, height: 26)).fill()

// "</>" on the board.
let style = NSMutableParagraphStyle()
style.alignment = .center
let mark = NSAttributedString(string: "</>", attributes: [
    .font: NSFont.monospacedSystemFont(ofSize: 150, weight: .bold),
    .foregroundColor: rgb(40, 100, 230),
    .paragraphStyle: style,
])
mark.draw(in: NSRect(x: board.minX, y: 470, width: board.width, height: 200))

// Three history rows.
let rows: [(CGFloat, NSColor)] = [(400, rgb(52, 120, 246)), (330, rgb(20, 184, 196)), (260, rgb(255, 159, 10))]
for (y, color) in rows {
    color.setFill()
    NSBezierPath(roundedRect: NSRect(x: 352, y: y, width: 44, height: 36), xRadius: 12, yRadius: 12).fill()
    rgb(200, 208, 222).setFill()
    NSBezierPath(roundedRect: NSRect(x: 416, y: y + 6, width: 256, height: 24), xRadius: 12, yRadius: 12).fill()
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print(out)
