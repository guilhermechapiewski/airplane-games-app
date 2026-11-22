// Combines screenshots into one grid image. Usage: swift tools/contact_sheet.swift out.png cols img1.png img2.png ...
import AppKit
let args = CommandLine.arguments
let out = args[1], cols = Int(args[2])!
let images = args.dropFirst(3).compactMap { NSImage(contentsOfFile: $0) }
let w: CGFloat = 400
let h = w * (images.first.map { $0.size.height / $0.size.width } ?? 2)
let rows = (images.count + cols - 1) / cols
let canvas = NSImage(size: NSSize(width: w * CGFloat(cols), height: h * CGFloat(rows)))
canvas.lockFocus()
NSColor.black.setFill(); NSRect(origin: .zero, size: canvas.size).fill()
for (i, img) in images.enumerated() {
    let x = CGFloat(i % cols) * w, y = CGFloat(rows - 1 - i / cols) * h
    img.draw(in: NSRect(x: x + 4, y: y + 4, width: w - 8, height: h - 8))
}
canvas.unlockFocus()
let rep = NSBitmapImageRep(data: canvas.tiffRepresentation!)!
try! rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])!.write(to: URL(fileURLWithPath: out))
