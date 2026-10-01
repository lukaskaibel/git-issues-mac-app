// Draws the app icon variants as 1024 px PNGs, plus a contact sheet.
//   swift Tools/make-icons.swift Design/icon-variants
import AppKit
import SwiftUI

let canvas: CGFloat = 1024
// macOS icon grid: an 824 pt rounded square centred on a 1024 pt canvas.
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
let plateRadius: CGFloat = 186

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func squircle(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    Path(roundedRect: rect, cornerRadius: radius, style: .continuous).cgPath
}

func gradient(_ context: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
    context.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

/// Draws the plate with its soft shadow, then runs `content` clipped to it. Origin is top-left.
func render(_ name: String, top: UInt32, bottom: UInt32, content: (CGContext) -> Void) -> NSImage {
    let image = NSImage(size: NSSize(width: canvas, height: canvas))
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas), bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    context.translateBy(x: 0, y: canvas)
    context.scaleBy(x: 1, y: -1)

    let shape = squircle(plate, plateRadius)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.32))
    context.addPath(shape)
    context.setFillColor(color(bottom))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    gradient(context, [color(top), color(bottom)], from: CGPoint(x: 0, y: plate.minY), to: CGPoint(x: 0, y: plate.maxY))
    content(context)
    context.restoreGState()

    // A hairline highlight along the top edge gives the plate some depth.
    context.saveGState()
    context.addPath(shape)
    context.setStrokeColor(color(0xFFFFFF, 0.10))
    context.setLineWidth(2)
    context.strokePath()
    context.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    image.addRepresentation(rep)
    return image
}

func fill(_ context: CGContext, _ rect: CGRect, radius: CGFloat, _ fill: CGColor) {
    context.addPath(squircle(rect, radius))
    context.setFillColor(fill)
    context.fillPath()
}

/// A status ring with a check mark, like the "done" glyph in the app.
func checkRing(_ context: CGContext, center: CGPoint, radius: CGFloat, ring: CGColor, mark: CGColor) {
    context.setFillColor(ring)
    context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    context.setStrokeColor(mark)
    context.setLineWidth(radius * 0.26)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.move(to: CGPoint(x: center.x - radius * 0.42, y: center.y + radius * 0.04))
    context.addLine(to: CGPoint(x: center.x - radius * 0.10, y: center.y + radius * 0.36))
    context.addLine(to: CGPoint(x: center.x + radius * 0.44, y: center.y - radius * 0.30))
    context.strokePath()
}

// Variant A: a card lifted off a dark board.
let lifted = render("A", top: 0x23262D, bottom: 0x0E0F12) { context in
    let laneWidth: CGFloat = 196
    for index in 0..<3 {
        let x = plate.minX + 84 + CGFloat(index) * (laneWidth + 34)
        fill(context, CGRect(x: x, y: plate.minY + 96, width: laneWidth, height: 640), radius: 36, color(0xFFFFFF, 0.045))
        let cards: [CGFloat] = index == 1 ? [0, 300] : [0, 150, 300]
        for offset in cards {
            fill(context, CGRect(x: x + 20, y: plate.minY + 120 + offset, width: laneWidth - 40, height: 118), radius: 24, color(0xFFFFFF, 0.085))
        }
    }
    context.saveGState()
    context.translateBy(x: 512, y: 530)
    context.rotate(by: -8 * .pi / 180)
    let card = CGRect(x: -190, y: -128, width: 380, height: 256)
    context.setShadow(offset: CGSize(width: 0, height: -34), blur: 70, color: color(0x000000, 0.55))
    context.addPath(squircle(card, 46))
    context.setFillColor(color(0x6F78E6))
    context.fillPath()
    context.setShadow(offset: .zero, blur: 0, color: nil)
    context.saveGState()
    context.addPath(squircle(card, 46))
    context.clip()
    gradient(context, [color(0x959CF7), color(0x5B63D3)], from: CGPoint(x: 0, y: card.minY), to: CGPoint(x: 0, y: card.maxY))
    context.restoreGState()
    checkRing(context, center: CGPoint(x: card.minX + 72, y: card.minY + 74), radius: 34, ring: color(0xFFFFFF), mark: color(0x5B63D3))
    fill(context, CGRect(x: card.minX + 44, y: card.minY + 138, width: 292, height: 26), radius: 13, color(0xFFFFFF, 0.92))
    fill(context, CGRect(x: card.minX + 44, y: card.minY + 184, width: 196, height: 26), radius: 13, color(0xFFFFFF, 0.55))
    context.restoreGState()
}

// Variant B: three columns on the accent colour.
let columns = render("B", top: 0x8E96F5, bottom: 0x4A52C4) { context in
    let width: CGFloat = 168
    let heights: [CGFloat] = [420, 560, 300]
    for (index, height) in heights.enumerated() {
        let x = plate.minX + 118 + CGFloat(index) * (width + 42)
        fill(context, CGRect(x: x, y: plate.minY + 132, width: width, height: height), radius: 44, color(0xFFFFFF, index == 1 ? 1 : 0.78))
    }
    checkRing(context, center: CGPoint(x: plate.minX + 118 + width + 42 + width / 2, y: plate.minY + 132 + 560 - 96), radius: 44, ring: color(0x5B63D3), mark: color(0xFFFFFF))
}

// Variant C: the "in progress" status ring.
let ring = render("C", top: 0x23262D, bottom: 0x0E0F12) { context in
    let center = CGPoint(x: 512, y: 512)
    context.setStrokeColor(color(0x8F96F2))
    context.setLineWidth(58)
    context.strokeEllipse(in: CGRect(x: center.x - 232, y: center.y - 232, width: 464, height: 464))
    context.setFillColor(color(0x8F96F2))
    context.move(to: center)
    context.addArc(center: center, radius: 150, startAngle: -.pi / 2, endAngle: .pi * 0.75, clockwise: false)
    context.closePath()
    context.fillPath()
}

// Variant D: stacked cards on a light plate.
let stack = render("D", top: 0xFFFFFF, bottom: 0xE6E8F0) { context in
    let cards: [(CGFloat, CGFloat, UInt32, CGFloat)] = [
        (-96, 150, 0xC9CCD6, -6), (0, 286, 0xF0B429, 0), (96, 422, 0x5B63D3, 6),
    ]
    for (dx, y, hex, angle) in cards {
        context.saveGState()
        context.translateBy(x: 512 + dx * 0.35, y: plate.minY + y + 100)
        context.rotate(by: angle * .pi / 180)
        let card = CGRect(x: -250, y: -100, width: 500, height: 200)
        context.setShadow(offset: CGSize(width: 0, height: -16), blur: 40, color: color(0x1A1B1E, 0.22))
        context.addPath(squircle(card, 44))
        context.setFillColor(color(0xFFFFFF))
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.setFillColor(color(hex))
        context.fillEllipse(in: CGRect(x: card.minX + 44, y: card.minY + 60, width: 80, height: 80))
        fill(context, CGRect(x: card.minX + 160, y: card.minY + 64, width: 280, height: 28), radius: 14, color(0x1A1B1E, 0.82))
        fill(context, CGRect(x: card.minX + 160, y: card.minY + 110, width: 180, height: 28), radius: 14, color(0x1A1B1E, 0.28))
        context.restoreGState()
    }
}

// MARK: Second round: a kanban board, with the finished card standing out.

struct BoardStyle {
    var top: UInt32
    var bottom: UInt32
    var lane: CGColor
    var card: CGColor
    var cardShadow: CGColor
    var line: CGColor
    /// Dot colours for the "to do" and "in progress" columns.
    var dots: [CGColor]
    var doneTop: UInt32
    var doneBottom: UInt32
    var doneMark: CGColor
    var doneInk: CGColor
    /// Tint whole cards per column instead of only the dot.
    var tinted: [CGColor]? = nil
}

func board(_ style: BoardStyle) -> NSImage {
    render("board", top: style.top, bottom: style.bottom) { context in
        let columnWidth: CGFloat = 208
        let gap: CGFloat = 20
        let left = plate.minX + (plate.width - 3 * columnWidth - 2 * gap) / 2
        let laneTop = plate.minY + 106
        let laneHeight: CGFloat = 612
        let cardHeight: CGFloat = 176
        let counts = [3, 2, 1]
        for column in 0..<3 {
            let x = left + CGFloat(column) * (columnWidth + gap)
            fill(context, CGRect(x: x, y: laneTop, width: columnWidth, height: laneHeight), radius: 50, style.lane)
            for row in 0..<counts[column] {
                let card = CGRect(x: x + 18, y: laneTop + 18 + CGFloat(row) * (cardHeight + 24), width: columnWidth - 36, height: cardHeight)
                let isDone = column == 2
                context.saveGState()
                context.setShadow(offset: CGSize(width: 0, height: isDone ? -16 : -6), blur: isDone ? 34 : 14, color: isDone ? color(style.doneBottom, 0.5) : style.cardShadow)
                context.addPath(squircle(card, 34))
                context.setFillColor(isDone ? color(style.doneBottom) : (style.tinted?[column] ?? style.card))
                context.fillPath()
                context.restoreGState()
                let ringCenter = CGPoint(x: card.minX + 44, y: card.minY + 50)
                let first = CGRect(x: card.minX + 24, y: card.minY + 98, width: card.width - 48, height: 20)
                let second = CGRect(x: card.minX + 24, y: card.minY + 132, width: (card.width - 48) * 0.6, height: 20)
                if isDone {
                    context.saveGState()
                    context.addPath(squircle(card, 34))
                    context.clip()
                    gradient(context, [color(style.doneTop), color(style.doneBottom)], from: CGPoint(x: 0, y: card.minY), to: CGPoint(x: 0, y: card.maxY))
                    context.restoreGState()
                    checkRing(context, center: ringCenter, radius: 26, ring: style.doneMark, mark: color(style.doneBottom))
                    fill(context, first, radius: 10, style.doneInk)
                    fill(context, second, radius: 10, style.doneInk.copy(alpha: style.doneInk.alpha * 0.55)!)
                } else {
                    let dot = style.tinted == nil ? style.dots[column] : style.line
                    context.setStrokeColor(dot)
                    context.setLineWidth(8)
                    let ring = CGRect(x: ringCenter.x - 20, y: ringCenter.y - 20, width: 40, height: 40)
                    context.strokeEllipse(in: ring)
                    if column == 1 {
                        context.setFillColor(dot)
                        context.move(to: ringCenter)
                        context.addArc(center: ringCenter, radius: 10, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
                        context.closePath()
                        context.fillPath()
                    }
                    fill(context, first, radius: 10, style.line)
                    fill(context, second, radius: 10, style.line.copy(alpha: style.line.alpha * 0.4)!)
                }
            }
        }
    }
}

// Variant E: light plate, white cards, the finished card in the accent colour.
let boardLight = board(BoardStyle(
    top: 0xFFFFFF, bottom: 0xE4E7F0, lane: color(0x1A1B1E, 0.055), card: color(0xFFFFFF), cardShadow: color(0x1A1B1E, 0.16),
    line: color(0x1A1B1E, 0.78), dots: [color(0xA4A9B6), color(0xF0A81E)],
    doneTop: 0x7F87EE, doneBottom: 0x5058CC, doneMark: color(0xFFFFFF), doneInk: color(0xFFFFFF, 0.92)
))

// Variant F: the same board on the dark plate.
let boardDark = board(BoardStyle(
    top: 0x262930, bottom: 0x0E0F12, lane: color(0xFFFFFF, 0.05), card: color(0x30343C), cardShadow: color(0x000000, 0.35),
    line: color(0xFFFFFF, 0.78), dots: [color(0x9AA0AC), color(0xF0B429)],
    doneTop: 0x959CF7, doneBottom: 0x5B63D3, doneMark: color(0xFFFFFF), doneInk: color(0xFFFFFF, 0.92)
))

// Variant G: accent plate with white cards; the finished card is the brightest thing on it.
let boardAccent = board(BoardStyle(
    top: 0x8E96F5, bottom: 0x4A52C4, lane: color(0xFFFFFF, 0.16), card: color(0xFFFFFF, 0.62), cardShadow: color(0x1E2470, 0.25),
    line: color(0x353CA8, 0.80), dots: [color(0x353CA8, 0.75), color(0x353CA8, 0.75)],
    doneTop: 0xFFFFFF, doneBottom: 0xF1F2FF, doneMark: color(0x4A52C4), doneInk: color(0x353CA8, 0.85)
))

// Variant H: dark plate, each column in its status colour.
let boardColour = board(BoardStyle(
    top: 0x262930, bottom: 0x0E0F12, lane: color(0xFFFFFF, 0.05), card: color(0x30343C), cardShadow: color(0x000000, 0.35),
    line: color(0x14161A, 0.72), dots: [color(0x14161A, 0.72), color(0x14161A, 0.72)],
    doneTop: 0x959CF7, doneBottom: 0x5B63D3, doneMark: color(0xFFFFFF), doneInk: color(0xFFFFFF, 0.92),
    tinted: [color(0xB9BECB), color(0xF2B53A), color(0x5B63D3)]
))

// MARK: Third round: the same idea with as few parts as possible.

enum Stage {
    case todo, doing, done
}

/// One card with a status ring and, optionally, text lines. The finished one is filled with the accent colour.
func simpleCard(_ context: CGContext, _ rect: CGRect, _ stage: Stage, radius: CGFloat, ring ringRadius: CGFloat, lines: Bool, horizontal: Bool = false) {
    let done = stage == .done
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: done ? -18 : -8), blur: done ? 38 : 18, color: done ? color(0x5058CC, 0.5) : color(0x1A1B1E, 0.16))
    context.addPath(squircle(rect, radius))
    context.setFillColor(done ? color(0x5058CC) : color(0xFFFFFF))
    context.fillPath()
    context.restoreGState()
    if done {
        context.saveGState()
        context.addPath(squircle(rect, radius))
        context.clip()
        gradient(context, [color(0x7F87EE), color(0x5058CC)], from: CGPoint(x: 0, y: rect.minY), to: CGPoint(x: 0, y: rect.maxY))
        context.restoreGState()
    }
    let center = horizontal
        ? CGPoint(x: rect.minX + rect.height / 2, y: rect.midY)
        : CGPoint(x: rect.midX, y: lines ? rect.minY + ringRadius + 34 : rect.midY)
    if done {
        checkRing(context, center: center, radius: ringRadius, ring: color(0xFFFFFF), mark: color(0x5058CC))
    } else {
        let tint = stage == .todo ? color(0xA4A9B6) : color(0xF0A81E)
        context.setStrokeColor(tint)
        context.setLineWidth(ringRadius * 0.36)
        let inset = ringRadius * 0.18
        context.strokeEllipse(in: CGRect(x: center.x - ringRadius + inset, y: center.y - ringRadius + inset, width: (ringRadius - inset) * 2, height: (ringRadius - inset) * 2))
        if stage == .doing {
            context.setFillColor(tint)
            context.move(to: center)
            context.addArc(center: center, radius: ringRadius * 0.46, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
            context.closePath()
            context.fillPath()
        }
    }
    guard lines else { return }
    let ink = done ? color(0xFFFFFF, 0.92) : color(0x1A1B1E, 0.78)
    if horizontal {
        let x = rect.minX + rect.height + 4
        fill(context, CGRect(x: x, y: rect.midY - 14, width: rect.maxX - x - 56, height: 28), radius: 14, ink)
    } else {
        let y = center.y + ringRadius + 34
        fill(context, CGRect(x: rect.minX + 30, y: y, width: rect.width - 60, height: 24), radius: 12, ink)
        fill(context, CGRect(x: rect.minX + 30, y: y + 42, width: (rect.width - 60) * 0.6, height: 24), radius: 12, ink.copy(alpha: ink.alpha * 0.45)!)
    }
}

// Variant I: three columns as plain bars of different heights, the last one finished.
let bars = render("I", top: 0xFFFFFF, bottom: 0xE4E7F0) { context in
    let width: CGFloat = 192
    let gap: CGFloat = 38
    let left = plate.minX + (plate.width - 3 * width - 2 * gap) / 2
    let heights: [CGFloat] = [440, 560, 330]
    for (index, stage) in [Stage.todo, .doing, .done].enumerated() {
        let rect = CGRect(x: left + CGFloat(index) * (width + gap), y: plate.minY + 132, width: width, height: heights[index])
        simpleCard(context, rect, stage, radius: 52, ring: 46, lines: false)
        // Rings sit near the top of each bar, like a column header.
        _ = rect
    }
}

// Variant J: three rows, like a checklist that knows about progress.
let rows = render("J", top: 0xFFFFFF, bottom: 0xE4E7F0) { context in
    let height: CGFloat = 168
    let gap: CGFloat = 30
    let top = plate.minY + (plate.height - 3 * height - 2 * gap) / 2
    for (index, stage) in [Stage.todo, .doing, .done].enumerated() {
        let rect = CGRect(x: plate.minX + 96, y: top + CGFloat(index) * (height + gap), width: plate.width - 192, height: height)
        simpleCard(context, rect, stage, radius: 50, ring: 42, lines: true, horizontal: true)
    }
}

// Variant K: two columns, three cards.
let twoColumns = render("K", top: 0xFFFFFF, bottom: 0xE4E7F0) { context in
    let width: CGFloat = 290
    let gap: CGFloat = 36
    let left = plate.minX + (plate.width - 2 * width - gap) / 2
    let top = plate.minY + 116
    fill(context, CGRect(x: left - 18, y: top - 18, width: width + 36, height: 628), radius: 62, color(0x1A1B1E, 0.05))
    fill(context, CGRect(x: left + width + gap - 18, y: top - 18, width: width + 36, height: 628), radius: 62, color(0x1A1B1E, 0.05))
    simpleCard(context, CGRect(x: left, y: top, width: width, height: 284), .todo, radius: 48, ring: 44, lines: true)
    simpleCard(context, CGRect(x: left, y: top + 308, width: width, height: 284), .doing, radius: 48, ring: 44, lines: true)
    simpleCard(context, CGRect(x: left + width + gap, y: top, width: width, height: 284), .done, radius: 48, ring: 44, lines: true)
}

// Variant L: one card per column, climbing towards done.
let rising = render("L", top: 0xFFFFFF, bottom: 0xE4E7F0) { context in
    let width: CGFloat = 208
    let gap: CGFloat = 22
    let left = plate.minX + (plate.width - 3 * width - 2 * gap) / 2
    let laneTop = plate.minY + 106
    let offsets: [CGFloat] = [340, 180, 20]
    for (index, stage) in [Stage.todo, .doing, .done].enumerated() {
        let x = left + CGFloat(index) * (width + gap)
        fill(context, CGRect(x: x, y: laneTop, width: width, height: 612), radius: 50, color(0x1A1B1E, 0.055))
        simpleCard(context, CGRect(x: x + 18, y: laneTop + offsets[index], width: width - 36, height: 250), stage, radius: 38, ring: 38, lines: true)
    }
}

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
func save(_ image: NSImage, _ name: String) throws {
    guard let rep = image.representations.first as? NSBitmapImageRep, let data = rep.representation(using: .png, properties: [:]) else { return }
    try data.write(to: output.appendingPathComponent(name))
}

/// All variants on a neutral ground, with letters underneath.
func contactSheet(_ variants: [(String, NSImage)], name: String) throws {
    let sheetSize = NSSize(width: 60 + CGFloat(variants.count) * 530 + 20, height: 680)
    let sheetRep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(sheetSize.width), pixelsHigh: Int(sheetSize.height), bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheetRep)
    NSColor(srgbRed: 0.93, green: 0.94, blue: 0.96, alpha: 1).setFill()
    NSRect(origin: .zero, size: sheetSize).fill()
    for (index, (variant, image)) in variants.enumerated() {
        let x = 60 + CGFloat(index) * 530
        image.draw(in: NSRect(x: x, y: 110, width: 500, height: 500))
        // Small sizes too: an icon has to read in the Dock and in Finder lists.
        image.draw(in: NSRect(x: x + 390, y: 34, width: 64, height: 64))
        image.draw(in: NSRect(x: x + 464, y: 50, width: 32, height: 32))
        let label = NSAttributedString(string: String(variant.prefix(1)), attributes: [
            .font: NSFont.systemFont(ofSize: 44, weight: .semibold),
            .foregroundColor: NSColor(srgbRed: 0.1, green: 0.1, blue: 0.12, alpha: 1),
        ])
        label.draw(at: NSPoint(x: x + 250 - label.size().width / 2, y: 40))
    }
    NSGraphicsContext.restoreGraphicsState()
    let sheet = NSImage(size: sheetSize)
    sheet.addRepresentation(sheetRep)
    try save(sheet, name)
}

let first: [(String, NSImage)] = [("A-lifted-card", lifted), ("B-columns", columns), ("C-status-ring", ring), ("D-card-stack", stack)]
let second: [(String, NSImage)] = [("E-board-light", boardLight), ("F-board-dark", boardDark), ("G-board-accent", boardAccent), ("H-board-colour", boardColour)]
let third: [(String, NSImage)] = [("I-three-bars", bars), ("J-three-rows", rows), ("K-two-columns", twoColumns), ("L-rising", rising)]
for (name, image) in first + second + third { try save(image, "icon-\(name).png") }
try contactSheet(first, name: "contact-sheet.png")
try contactSheet(second, name: "contact-sheet-2.png")
try contactSheet(third, name: "contact-sheet-3.png")
print("Wrote \(first.count + second.count + third.count) icons and three contact sheets to \(output.path)")
