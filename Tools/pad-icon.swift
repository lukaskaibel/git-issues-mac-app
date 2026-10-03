// Helpers for Tools/render-icons.sh.
//   swift Tools/pad-icon.swift <in> <out>              puts a full-bleed icon on the macOS icon grid
//   swift Tools/pad-icon.swift --split <a> <b> <out>   light and dark halves, for the "Automatic" choice
import AppKit

let canvas: CGFloat = 1024
let arguments = Array(CommandLine.arguments.dropFirst())

func write(_ draw: (CGContext) -> Void, to path: String) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas), bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(NSGraphicsContext.current!.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

func image(_ path: String) -> CGImage {
    NSImage(contentsOfFile: path)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
}

if arguments.first == "--split" {
    let light = image(arguments[1])
    let dark = image(arguments[2])
    write({ context in
        let full = CGRect(x: 0, y: 0, width: canvas, height: canvas)
        context.draw(light, in: full)
        // The lower right half in dark, split along the diagonal.
        context.move(to: CGPoint(x: canvas, y: canvas))
        context.addLine(to: CGPoint(x: canvas, y: 0))
        context.addLine(to: CGPoint(x: 0, y: 0))
        context.closePath()
        context.clip()
        context.draw(dark, in: full)
    }, to: arguments[3])
} else {
    let icon = image(arguments[0])
    write({ context in
        // A soft shadow under the body, as the Dock draws for bundle icons.
        context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.28))
        context.draw(icon, in: CGRect(x: 100, y: 100, width: 824, height: 824))
    }, to: arguments[1])
}
