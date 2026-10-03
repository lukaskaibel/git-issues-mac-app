// Draws the "lifted card" app icon as Icon Composer documents: a card in the accent colour, tilted, over a faint
// board. The app icon follows the system's light and dark appearance; the violet one is offered in Settings.
//   swift Tools/make-card-icon.swift
// Then Tools/render-icons.sh turns the documents into the PNGs the app and the README use.
import AppKit
import SwiftUI

let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// The colour as Icon Composer writes it.
func iconColor(_ hex: UInt32, _ alpha: CGFloat = 1) -> String {
    let parts = [(hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF].map { String(format: "%.5f", CGFloat($0) / 255) }
    return "srgb:" + parts.joined(separator: ",") + String(format: ",%.5f", alpha)
}

func squircle(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    Path(roundedRect: rect, cornerRadius: radius, style: .continuous).cgPath
}

func fill(_ context: CGContext, _ rect: CGRect, radius: CGFloat, _ fill: CGColor) {
    context.addPath(squircle(rect, radius))
    context.setFillColor(fill)
    context.fillPath()
}

/// A transparent 1024 px layer. Origin is top-left.
func layer(_ draw: (CGContext) -> Void) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas), bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    context.translateBy(x: 0, y: canvas)
    context.scaleBy(x: 1, y: -1)
    draw(context)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

/// The board behind the card: three columns of cards, running off the bottom edge.
func tiles(_ tint: CGColor) -> Data {
    layer { context in
        let width: CGFloat = 248
        let height: CGFloat = 168
        let gap: CGFloat = 34
        let left = (canvas - 3 * width - 2 * gap) / 2
        for column in 0..<3 {
            for row in 0..<4 {
                let rect = CGRect(x: left + CGFloat(column) * (width + gap), y: 118 + CGFloat(row) * (height + gap), width: width, height: height)
                fill(context, rect, radius: 40, tint)
            }
        }
    }
}

struct CardColors {
    var top: CGColor
    var bottom: CGColor
    var ring: CGColor
    var mark: CGColor
    var ink: CGColor
    var inkSoft: CGColor
}

/// The lifted card: a done ring and two lines of text, turned a little as if just picked up.
func card(_ colors: CardColors) -> Data {
    layer { context in
        context.translateBy(x: 540, y: 500)
        context.rotate(by: -11 * .pi / 180)
        let rect = CGRect(x: -290, y: -186, width: 580, height: 372)
        let shape = squircle(rect, 76)
        context.saveGState()
        context.addPath(shape)
        context.clip()
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [colors.top, colors.bottom] as CFArray, locations: nil)!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
        context.restoreGState()

        let center = CGPoint(x: rect.minX + 108, y: rect.minY + 108)
        let radius: CGFloat = 52
        context.setFillColor(colors.ring)
        context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.setStrokeColor(colors.mark)
        context.setLineWidth(radius * 0.27)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.move(to: CGPoint(x: center.x - radius * 0.42, y: center.y + radius * 0.04))
        context.addLine(to: CGPoint(x: center.x - radius * 0.10, y: center.y + radius * 0.36))
        context.addLine(to: CGPoint(x: center.x + radius * 0.44, y: center.y - radius * 0.30))
        context.strokePath()

        fill(context, CGRect(x: rect.minX + 56, y: rect.minY + 210, width: 420, height: 40), radius: 20, colors.ink)
        fill(context, CGRect(x: rect.minX + 56, y: rect.minY + 280, width: 270, height: 40), radius: 20, colors.inkSoft)
    }
}

struct Look {
    var fillTop: UInt32
    var fillBottom: UInt32
    var tiles: String
}

func gradientFill(_ look: Look) -> [String: Any] {
    [
        "linear-gradient": [iconColor(look.fillTop), iconColor(look.fillBottom)],
        "orientation": ["start": ["x": 0.5, "y": 0], "stop": ["x": 0.5, "y": 1]],
    ]
}

/// Writes an Icon Composer document. `dark` is the look for the dark appearance, if it differs.
func document(at url: URL, light: Look, dark: Look?, card cardImage: String) throws {
    var fill: [[String: Any]] = [["value": gradientFill(light)]]
    var tileNames: [[String: Any]] = [["value": light.tiles]]
    if let dark {
        fill.append(["appearance": "dark", "value": gradientFill(dark)])
        tileNames.append(["appearance": "dark", "value": dark.tiles])
    }
    let json: [String: Any] = [
        "fill-specializations": fill,
        "groups": [
            [
                "name": "Card",
                "layers": [["name": "card", "image-name": cardImage, "glass": true]],
                "shadow": ["kind": "layer-color", "opacity": 0.6],
                "translucency": ["enabled": false, "value": 0.4],
            ],
            [
                "name": "Board",
                "layers": [["name": "tiles", "image-name-specializations": tileNames, "glass": false]],
                "shadow": ["kind": "none", "opacity": 0.5],
                "translucency": ["enabled": false, "value": 0.5],
            ],
        ],
        "supported-platforms": ["squares": ["macOS"]],
    ]
    try FileManager.default.createDirectory(at: url.appendingPathComponent("Assets"), withIntermediateDirectories: true)
    let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url.appendingPathComponent("icon.json"))
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appIcon = root.appendingPathComponent("GitIssues/AppIcon.icon")
let violetIcon = root.appendingPathComponent("Design/AppIcon-Violet.icon")

let accent = CardColors(
    top: color(0x969DF8), bottom: color(0x5A62D6), ring: color(0xFFFFFF), mark: color(0x5A62D6),
    ink: color(0xFFFFFF, 0.94), inkSoft: color(0xFFFFFF, 0.58)
)
let white = CardColors(
    top: color(0xFFFFFF), bottom: color(0xEEF0FF), ring: color(0x5A62D6), mark: color(0xFFFFFF),
    ink: color(0x3A41B0, 0.88), inkSoft: color(0x3A41B0, 0.40)
)

try document(
    at: appIcon,
    light: Look(fillTop: 0xFFFFFF, fillBottom: 0xE3E6EF, tiles: "tiles-light.png"),
    dark: Look(fillTop: 0x2A2D35, fillBottom: 0x0F1013, tiles: "tiles-dark.png"),
    card: "card.png"
)
try tiles(color(0x1A1B1E, 0.06)).write(to: appIcon.appendingPathComponent("Assets/tiles-light.png"))
try tiles(color(0xFFFFFF, 0.06)).write(to: appIcon.appendingPathComponent("Assets/tiles-dark.png"))
try card(accent).write(to: appIcon.appendingPathComponent("Assets/card.png"))

try document(
    at: violetIcon,
    light: Look(fillTop: 0x9198F6, fillBottom: 0x4C54C6, tiles: "tiles.png"),
    dark: nil,
    card: "card.png"
)
try tiles(color(0xFFFFFF, 0.13)).write(to: violetIcon.appendingPathComponent("Assets/tiles.png"))
try card(white).write(to: violetIcon.appendingPathComponent("Assets/card.png"))

print("Wrote \(appIcon.lastPathComponent) and \(violetIcon.lastPathComponent)")
