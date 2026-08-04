import AppKit

// Renders the 1024×1024 master app icon PNG for GitHub Notifier:
// a rounded-square indigo gradient with a white bell and a red notification dot.
// Usage: swift tools/make_icon.swift <output.png>

// Touch the shared app so AppKit drawing/SF Symbols are available offscreen.
_ = NSApplication.shared

let side: CGFloat = 1024
let canvas = NSRect(x: 0, y: 0, width: side, height: side)

/// Returns a copy of `image` tinted to a solid color (preserving alpha).
func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
    let out = NSImage(size: image.size)
    out.lockFocus()
    image.draw(at: .zero, from: NSRect(origin: .zero, size: image.size), operation: .sourceOver, fraction: 1)
    color.set()
    NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
    out.unlockFocus()
    return out
}

let master = NSImage(size: canvas.size)
master.lockFocus()

// 1) Rounded-square background with a diagonal indigo→violet gradient.
let pad: CGFloat = 84
let bgRect = canvas.insetBy(dx: pad, dy: pad)
let bg = NSBezierPath(roundedRect: bgRect, xRadius: 210, yRadius: 210)
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.40, green: 0.44, blue: 1.00, alpha: 1),
    NSColor(srgbRed: 0.29, green: 0.20, blue: 0.86, alpha: 1)
])!
gradient.draw(in: bg, angle: -60)

// Subtle top highlight for depth.
let highlight = NSGradient(colors: [
    NSColor(white: 1, alpha: 0.18),
    NSColor(white: 1, alpha: 0.0)
])!
highlight.draw(in: bg, angle: -90)

// 2) White bell glyph, centered.
let bellConfig = NSImage.SymbolConfiguration(pointSize: 480, weight: .semibold)
if let bellBase = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(bellConfig) {
    let white = tinted(bellBase, .white)
    let bs = white.size
    let bellRect = NSRect(
        x: (side - bs.width) / 2,
        y: (side - bs.height) / 2 - 8,
        width: bs.width,
        height: bs.height
    )
    white.draw(in: bellRect)
}

// 3) Red notification dot (with a thin gradient-matched ring for separation).
let dotD: CGFloat = 232
let dotRect = NSRect(x: side * 0.585, y: side * 0.60, width: dotD, height: dotD)
let ring = dotRect.insetBy(dx: -22, dy: -22)
NSColor(srgbRed: 0.29, green: 0.20, blue: 0.86, alpha: 1).setFill()
NSBezierPath(ovalIn: ring).fill()
NSColor(srgbRed: 1.0, green: 0.23, blue: 0.19, alpha: 1).setFill()
NSBezierPath(ovalIn: dotRect).fill()

master.unlockFocus()

// Encode PNG.
guard let tiff = master.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("Failed to render icon\n".data(using: .utf8)!)
    exit(1)
}
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-master.png"
do {
    try png.write(to: URL(fileURLWithPath: outPath))
    print("Wrote \(outPath)")
} catch {
    FileHandle.standardError.write("Write failed: \(error)\n".data(using: .utf8)!)
    exit(1)
}
