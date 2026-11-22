// Renders the app icon (1024x1024 PNG). Run: swift tools/make_icon.swift <output.png>
import AppKit
import CoreGraphics

let size = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r/255, g/255, b/255, a])!
}
// Sky gradient (bottom → top in CG coordinates)
let grad = CGGradient(colorsSpace: cs, colors: [c(28, 40, 110), c(66, 122, 230), c(126, 196, 255)] as CFArray,
                      locations: [0, 0.6, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: CGFloat(size)), options: [])

// Soft clouds
ctx.setFillColor(c(255, 255, 255, 0.16))
for (x, y, r) in [(170.0, 830.0, 90.0), (260, 860, 110), (360, 830, 80), (800, 140, 100), (900, 170, 80), (700, 150, 70)] {
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}

// 2x2 tile grid
let tileColors = [c(255, 196, 61), c(255, 107, 107), c(72, 219, 160), c(173, 130, 255)]
let tile: CGFloat = 230, gap: CGFloat = 36
let gridW = tile * 2 + gap
let ox = (CGFloat(size) - gridW) / 2, oy = (CGFloat(size) - gridW) / 2 - 70
for i in 0..<4 {
    let col = CGFloat(i % 2), row = CGFloat(1 - i / 2)
    let rect = CGRect(x: ox + col * (tile + gap), y: oy + row * (tile + gap), width: tile, height: tile)
    // shadow
    ctx.setFillColor(c(10, 20, 60, 0.28))
    ctx.addPath(CGPath(roundedRect: rect.offsetBy(dx: 0, dy: -14), cornerWidth: 54, cornerHeight: 54, transform: nil))
    ctx.fillPath()
    ctx.setFillColor(tileColors[i])
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 54, cornerHeight: 54, transform: nil))
    ctx.fillPath()
    // highlight
    ctx.setFillColor(c(255, 255, 255, 0.22))
    ctx.addPath(CGPath(roundedRect: CGRect(x: rect.minX + 18, y: rect.midY + 20, width: rect.width - 36, height: rect.height / 2 - 38),
                       cornerWidth: 36, cornerHeight: 36, transform: nil))
    ctx.fillPath()
}

// Paper plane flying across the top-right
ctx.saveGState()
ctx.translateBy(x: 790, y: 880)
ctx.scaleBy(x: 0.78, y: 0.78)
ctx.rotate(by: 0.32)
let plane = CGMutablePath()
plane.move(to: CGPoint(x: 170, y: 0))
plane.addLine(to: CGPoint(x: -150, y: 95))
plane.addLine(to: CGPoint(x: -70, y: 0))
plane.addLine(to: CGPoint(x: -150, y: -95))
plane.closeSubpath()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: c(10, 20, 60, 0.35))
ctx.setFillColor(c(255, 255, 255))
ctx.addPath(plane); ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
let fold = CGMutablePath()
fold.move(to: CGPoint(x: 170, y: 0))
fold.addLine(to: CGPoint(x: -70, y: 0))
fold.addLine(to: CGPoint(x: -150, y: -95))
fold.closeSubpath()
ctx.setFillColor(c(214, 226, 248))
ctx.addPath(fold); ctx.fillPath()
ctx.restoreGState()

// Dashed trail
ctx.setStrokeColor(c(255, 255, 255, 0.7))
ctx.setLineWidth(16)
ctx.setLineCap(.round)
ctx.setLineDash(phase: 0, lengths: [2, 40])
ctx.move(to: CGPoint(x: 110, y: 760))
ctx.addCurve(to: CGPoint(x: 640, y: 830), control1: CGPoint(x: 260, y: 900), control2: CGPoint(x: 460, y: 740))
ctx.strokePath()

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
