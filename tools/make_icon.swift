// Renders the app icon (1024x1024 PNG): an airplane window at sunset, shade half down, with a
// card and a die floating by. Variant "b" is the shipped icon; "a" (day) and "c" (bold die) were
// the alternatives considered.
// Run: swift tools/make_icon.swift b AirplaneModeGames/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import AppKit
import CoreGraphics

let variant = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "b"
let out = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "AppIcon.png"
let size: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
                                         CGFloat(hex & 0xFF) / 255, a])!
}
func gradient(_ colors: [UInt32], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: cs, colors: colors.map { c($0) } as CFArray, locations: locations)!
}
func roundedRect(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}
func fill(_ path: CGPath, _ color: CGColor) {
    ctx.addPath(path); ctx.setFillColor(color); ctx.fillPath()
}
func linear(_ path: CGPath, _ g: CGGradient, from: CGPoint, to: CGPoint) {
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}
/// A flat-bottomed cumulus cloud: puffs on top of a rounded base, drawn as one shape.
func cloud(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat, _ color: CGColor) {
    let path = CGMutablePath()
    path.addPath(roundedRect(CGRect(x: x - 1.1 * s, y: y - 0.35 * s, width: 2.2 * s, height: 0.7 * s), 0.35 * s))
    for (dx, dy, r) in [(-0.5, 0.2, 0.42), (0.1, 0.38, 0.58), (0.65, 0.15, 0.36)] {
        path.addEllipse(in: CGRect(x: x + dx * s - r * s, y: y + dy * s - r * s, width: 2 * r * s, height: 2 * r * s))
    }
    ctx.addPath(path); ctx.setFillColor(color); ctx.fillPath(using: .winding)
}
func text(_ s: String, _ font: NSFont, _ color: NSColor, at p: CGPoint) {
    let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
    let b = a.size()
    a.draw(at: CGPoint(x: p.x - b.width / 2, y: p.y - b.height / 2))
}
func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded)!, size: size) ?? base
}

/// A die face showing `pips` (5 by default), centered at `center`, rotated by `angle` degrees.
func die(_ center: CGPoint, _ side: CGFloat, _ angle: CGFloat, body: UInt32 = 0xFFFFFF, pip: UInt32 = 0xE5484D) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: angle * .pi / 180)
    let r = CGRect(x: -side / 2, y: -side / 2, width: side, height: side)
    fill(roundedRect(r.offsetBy(dx: 0, dy: -side * 0.06), side * 0.22), c(0x0B1530, 0.28))
    linear(roundedRect(r, side * 0.22), gradient([0xE9EDF5, body], [0, 1]), from: CGPoint(x: 0, y: -side / 2), to: CGPoint(x: 0, y: side / 2))
    let d = side * 0.27, pr = side * 0.095
    for (x, y) in [(-d, d), (d, d), (0, 0), (-d, -d), (d, -d)] {
        ctx.setFillColor(c(pip)); ctx.fillEllipse(in: CGRect(x: x - pr, y: y - pr, width: 2 * pr, height: 2 * pr))
    }
    ctx.restoreGState()
}

/// An ace of spades, centered at `center`, rotated by `angle` degrees.
func card(_ center: CGPoint, _ w: CGFloat, _ angle: CGFloat) {
    let h = w * 1.4
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: angle * .pi / 180)
    let r = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
    fill(roundedRect(r.offsetBy(dx: 0, dy: -w * 0.06), w * 0.12), c(0x0B1530, 0.28))
    fill(roundedRect(r, w * 0.12), c(0xFFFFFF))
    text("♠", rounded(w * 0.78, .black), NSColor(cgColor: c(0x1C2233))!, at: CGPoint(x: 0, y: -h * 0.02))
    text("A", rounded(w * 0.26, .heavy), NSColor(cgColor: c(0x1C2233))!, at: CGPoint(x: -w * 0.3, y: h * 0.36))
    ctx.restoreGState()
}

// MARK: Palettes

struct Look {
    var wall: [UInt32]          // cabin wall, top → bottom
    var frame: [UInt32]         // window bezel
    var sky: [UInt32]           // sky, top → bottom
    var cloud: CGColor
    var shade: Bool
}
let looks: [String: Look] = [
    "a": Look(wall: [0xF6F1E8, 0xE6DED1], frame: [0xFFFFFF, 0xD9DEE8], sky: [0x3D8BFD, 0x7CC4FF, 0xBFE6FF],
              cloud: c(0xFFFFFF, 0.9), shade: false),
    "b": Look(wall: [0x26315A, 0x141B36], frame: [0xF2F4F8, 0xB8C0D2], sky: [0x6A4BE0, 0xF0527A, 0xFFB547],
              cloud: c(0xFFE2C4, 0.85), shade: true),
    "c": Look(wall: [0x6EC6FF, 0x2F8FD8], frame: [0xFFFFFF, 0xFFFFFF], sky: [0x1E5FCF, 0x3D8BFD, 0x7CC4FF],
              cloud: c(0xFFFFFF, 0.85), shade: false),
]
let look = looks[variant] ?? looks["a"]!

// MARK: Draw

// Cabin wall
let full = CGRect(x: 0, y: 0, width: size, height: size)
linear(CGPath(rect: full, transform: nil), gradient(look.wall.reversed(), [0, 1]),
       from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: size))

// Window: an airplane window is a rounded vertical oval inside a thick bezel.
let window = CGRect(x: size / 2 - 300, y: size / 2 - 370, width: 600, height: 740)
let bezel = window.insetBy(dx: -62, dy: -62)
let windowPath = roundedRect(window, 290)
let bezelPath = roundedRect(bezel, 352)
fill(roundedRect(bezel.offsetBy(dx: 0, dy: -22), 352), c(0x0B1530, variant == "c" ? 0.22 : 0.3))
linear(bezelPath, gradient(look.frame.reversed(), [0, 1]), from: CGPoint(x: 0, y: bezel.minY), to: CGPoint(x: 0, y: bezel.maxY))

// Sky inside the window
ctx.saveGState()
ctx.addPath(windowPath); ctx.clip()
linear(windowPath, gradient(look.sky.reversed(), [0, 0.55, 1].reversed()), from: CGPoint(x: 0, y: window.maxY), to: CGPoint(x: 0, y: window.minY))
cloud(window.minX + 150, window.minY + 150, 120, look.cloud)
cloud(window.maxX - 110, window.minY + 300, 90, look.cloud)
cloud(window.minX + 120, window.maxY - 170, 70, look.cloud.copy(alpha: 0.6)!)

switch variant {
case "c":
    die(CGPoint(x: size / 2, y: size / 2 - 10), 330, -12)
case "b":
    // Lower, clear of the shade.
    card(CGPoint(x: size / 2 - 95, y: size / 2 - 110), 220, -14)
    die(CGPoint(x: size / 2 + 125, y: size / 2 - 215), 180, 18)
default:
    card(CGPoint(x: size / 2 - 95, y: size / 2 - 40), 230, -14)
    die(CGPoint(x: size / 2 + 120, y: size / 2 - 150), 190, 18)
}

if look.shade {
    // The window shade, pulled a third of the way down.
    let shade = CGRect(x: window.minX, y: window.maxY - 250, width: window.width, height: 250)
    linear(CGPath(rect: shade, transform: nil), gradient([0xC9CFDB, 0xF2F4F8], [0, 1]),
           from: CGPoint(x: 0, y: shade.minY), to: CGPoint(x: 0, y: shade.maxY))
    fill(CGPath(rect: CGRect(x: shade.minX, y: shade.minY - 6, width: shade.width, height: 22), transform: nil), c(0xA9B1C2))
    fill(roundedRect(CGRect(x: size / 2 - 60, y: shade.minY + 10, width: 120, height: 26), 13), c(0x8C93A3))
}

// Inner shadow along the top of the window glass
ctx.setStrokeColor(c(0x0B1530, 0.22)); ctx.setLineWidth(26)
ctx.addPath(windowPath); ctx.strokePath()
ctx.restoreGState()

// Thin inner rim
ctx.setStrokeColor(c(0x0B1530, 0.12)); ctx.setLineWidth(6)
ctx.addPath(windowPath); ctx.strokePath()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
