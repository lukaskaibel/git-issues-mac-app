import SwiftUI

/// What a board card shows, gathered up front so drawing needs no lookups.
struct CardModel: Equatable {
    var item: Item
    var priority: PriorityLevel
    var showsPriority: Bool
    /// Repository names only matter on boards that span more than one.
    var showsRepo: Bool
}

extension AppModel {
    func cardModel(for item: Item) -> CardModel {
        CardModel(
            item: item,
            priority: priorityLevel(of: item),
            showsPriority: project(of: item)?.priorityFieldId != nil,
            showsRepo: repos(projectId: item.projectId).count > 1
        )
    }
}

/// A board card, painted in a single pass at a height worked out in advance. Built from separate
/// views, a card takes over ten milliseconds to create and measure, which shows as stutter when a
/// long column scrolls.
struct CardView: View, Equatable {
    var card: CardModel
    var width: CGFloat
    var highlighted = false
    var lifted = false
    /// Changes when avatar images finish loading, so cards repaint with them.
    var avatarVersion = 0

    static let padding = CGSize(width: 12, height: 10)
    static let lineHeight: CGFloat = 16

    var body: some View {
        let titleHeight = Self.titleHeight(card.item.title, width: width - 2 * Self.padding.width)
        Canvas { context, size in
            CardPainter(context: context, size: size, titleHeight: titleHeight).draw(self)
        }
        .frame(width: width, height: Self.height(titleHeight: titleHeight))
        .accessibilityElement()
        .accessibilityLabel("\(card.item.displayNumber) \(card.item.title)")
        .accessibilityAddTraits(.isButton)
    }

    static func height(titleHeight: CGFloat) -> CGFloat {
        padding.height + 18 + 6 + titleHeight + 6 + 20 + padding.height
    }

    private static let titleFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    private static let heights = NSCache<NSString, NSNumber>()

    /// Height of the title when wrapped to at most three lines.
    static func titleHeight(_ title: String, width: CGFloat) -> CGFloat {
        let key = "\(Int(width))|\(title)" as NSString
        if let cached = heights.object(forKey: key) { return CGFloat(cached.doubleValue) }
        let bounds = NSAttributedString(string: title, attributes: [.font: titleFont]).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let lines = min(3, max(1, Int((bounds.height / lineHeight).rounded())))
        let height = CGFloat(lines) * lineHeight
        heights.setObject(NSNumber(value: Double(height)), forKey: key)
        return height
    }
}

private struct CardPainter {
    var context: GraphicsContext
    var size: CGSize
    var titleHeight: CGFloat

    func draw(_ view: CardView) {
        let card = view.card
        let item = card.item
        let padding = CardView.padding
        let outline = Path(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5), cornerRadius: 8, style: .continuous)
        let fill = view.lifted ? Theme.cardLifted : (view.highlighted ? Theme.cardHover : Theme.card)
        let border = view.lifted ? Theme.cardLiftedBorder : (view.highlighted ? Theme.cardHoverBorder : Theme.cardBorder)
        context.fill(outline, with: .color(fill))
        context.stroke(outline, with: .color(border), lineWidth: 1)

        // Top line: number, repository, pull-request mark, and assignees on the right.
        let topY = padding.height + 9
        var x = padding.width
        let number = context.resolve(
            Text(item.displayNumber).font(.small).monospacedDigit()
                .foregroundStyle(view.lifted ? Theme.textSecondary : Theme.textTertiary)
        )
        context.draw(number, at: CGPoint(x: x, y: topY), anchor: .leading)
        x += number.measure(in: CGSize(width: 200, height: 40)).width + 6
        if card.showsRepo, let repo = item.repoShortName {
            let text = context.resolve(Text(repo).font(.small).foregroundStyle(Theme.textTertiary))
            let width = min(text.measure(in: CGSize(width: 400, height: 40)).width, size.width - x - 80)
            if width > 20 {
                context.draw(text, in: CGRect(x: x, y: topY - 8, width: width, height: 16))
                x += width + 6
            }
        }
        if item.kind == .pullRequest {
            context.draw(
                Text(Image(systemName: "arrow.triangle.pull")).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.textTertiary),
                at: CGPoint(x: x, y: topY), anchor: .leading
            )
        }
        drawAvatars(item.assignees, rightEdge: size.width - padding.width, midY: topY, ring: fill)

        // Title, wrapped to at most three lines.
        let titleRect = CGRect(x: padding.width, y: padding.height + 18 + 6, width: size.width - 2 * padding.width, height: titleHeight)
        context.draw(Text(item.title).font(.uiMedium).foregroundStyle(Theme.text), in: titleRect)

        // Bottom line: priority, labels, sub-issue progress.
        let bottomY = titleRect.maxY + 6 + 10
        x = padding.width
        if card.showsPriority {
            drawPriority(card.priority, x: x, midY: bottomY)
            x += 14 + 6
        }
        let limit = size.width - padding.width
        var shown = 0
        for label in item.labels.prefix(2) {
            let text = context.resolve(Text(label.name).font(.tiny).foregroundStyle(Theme.textSecondary))
            let width = text.measure(in: CGSize(width: 400, height: 40)).width + 7 + 7 + 5 + 7
            guard x + width <= limit else { break }
            let rect = CGRect(x: x, y: bottomY - 10, width: width, height: 20)
            chip(rect)
            context.fill(Path(ellipseIn: CGRect(x: rect.minX + 7, y: bottomY - 3.5, width: 7, height: 7)), with: .color(Theme.labelColor(label.color)))
            context.draw(text, at: CGPoint(x: rect.minX + 19, y: bottomY), anchor: .leading)
            x = rect.maxX + 6
            shown += 1
        }
        if item.labels.count > shown, shown > 0 {
            let text = context.resolve(Text("+\(item.labels.count - shown)").font(.tiny).foregroundStyle(Theme.textSecondary))
            let width = text.measure(in: CGSize(width: 100, height: 40)).width + 14
            if x + width <= limit {
                let rect = CGRect(x: x, y: bottomY - 10, width: width, height: 20)
                chip(rect)
                context.draw(text, at: CGPoint(x: rect.minX + 7, y: bottomY), anchor: .leading)
                x = rect.maxX + 6
            }
        }
        if item.subTotal > 0 {
            let text = context.resolve(
                Text("\(item.subCompleted)/\(item.subTotal)").font(.tiny).monospacedDigit().foregroundStyle(Theme.textSecondary)
            )
            let width = text.measure(in: CGSize(width: 200, height: 40)).width + 7 + 11 + 4 + 7
            if x + width <= limit {
                let rect = CGRect(x: x, y: bottomY - 10, width: width, height: 20)
                chip(rect)
                let origin = CGPoint(x: rect.minX + 7, y: bottomY - 5.5)
                var glyph = Path()
                glyph.move(to: CGPoint(x: origin.x + 2.3, y: origin.y + 1.8))
                glyph.addLine(to: CGPoint(x: origin.x + 2.3, y: origin.y + 5.5))
                glyph.addQuadCurve(to: CGPoint(x: origin.x + 4.1, y: origin.y + 7.3), control: CGPoint(x: origin.x + 2.3, y: origin.y + 7.3))
                glyph.addLine(to: CGPoint(x: origin.x + 6, y: origin.y + 7.3))
                context.stroke(glyph, with: .color(Theme.textSecondary), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                context.stroke(
                    Path(ellipseIn: CGRect(x: origin.x + 6.2, y: origin.y + 5.8, width: 3.1, height: 3.1)),
                    with: .color(Theme.textSecondary), lineWidth: 1.2
                )
                context.draw(text, at: CGPoint(x: rect.minX + 7 + 11 + 4, y: bottomY), anchor: .leading)
            }
        }
    }

    private func chip(_ rect: CGRect) {
        context.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 10), with: .color(Theme.chipBorder), lineWidth: 1)
    }

    private func drawPriority(_ level: PriorityLevel, x: CGFloat, midY: CGFloat) {
        if level == .urgent {
            let rect = CGRect(x: x + 1, y: midY - 6, width: 12, height: 12)
            context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(Theme.urgent))
            context.draw(
                Text("!").font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(Theme.onColor),
                at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center
            )
            return
        }
        let bars: [(CGFloat, Bool)] = [(4, level >= .low), (7, level >= .medium), (10, level >= .high)]
        for (index, bar) in bars.enumerated() {
            let rect = CGRect(x: x + CGFloat(index) * 5, y: midY + 6 - bar.0, width: 3, height: bar.0)
            context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(bar.1 ? Theme.textBody : Theme.barOff))
        }
    }

    private func drawAvatars(_ people: [Person], rightEdge: CGFloat, midY: CGFloat, ring: Color) {
        let shown = Array(people.prefix(3))
        let diameter: CGFloat = 18
        for (index, person) in shown.enumerated().reversed() {
            let offset = CGFloat(shown.count - 1 - index) * 13
            let rect = CGRect(x: rightEdge - diameter - offset, y: midY - diameter / 2, width: diameter, height: diameter)
            // A ring in the card colour separates overlapping avatars.
            if shown.count > 1 {
                context.fill(Path(ellipseIn: rect.insetBy(dx: -1.5, dy: -1.5)), with: .color(ring))
            }
            if let url = person.avatarUrl, let image = AvatarCache.shared.cached(url) {
                var clipped = context
                clipped.clip(to: Path(ellipseIn: rect))
                clipped.draw(Image(nsImage: image).interpolation(.high), in: rect)
            } else {
                context.fill(Path(ellipseIn: rect), with: .color(Avatar.color(for: person.login)))
                context.draw(
                    Text(String(person.login.prefix(2)).uppercased())
                        .font(.system(size: 8, weight: .bold)).foregroundStyle(Color(hex: 0x111214)),
                    at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center
                )
            }
        }
    }
}

/// Right-click menu shared by cards and list rows.
struct ItemContextMenu: View {
    @Environment(AppModel.self) private var model
    var item: Item

    var body: some View {
        Menu("Status") {
            ForEach(model.statusOptions(projectId: item.projectId)) { option in
                Button {
                    withAnimation(Theme.spring) { model.setStatus(item, to: option) }
                } label: {
                    if item.statusId == option.id {
                        Label(option.name, systemImage: "checkmark")
                    } else {
                        Text(option.name)
                    }
                }
            }
        }
        let priorities = model.priorityOptions(projectId: item.projectId)
        if !priorities.isEmpty {
            Menu("Priority") {
                Button("No priority") { model.setPriority(item, to: nil) }
                ForEach(priorities) { option in
                    Button {
                        model.setPriority(item, to: option)
                    } label: {
                        if item.priorityId == option.id {
                            Label(option.name, systemImage: "checkmark")
                        } else {
                            Text(option.name)
                        }
                    }
                }
            }
        }
        if item.kind != .draft, let viewer = model.viewer {
            let mine = item.assignees.contains { $0.id == viewer.id }
            Button(mine ? "Unassign Me" : "Assign to Me") {
                model.toggleAssignee(item, viewer.person)
            }
        }
        Divider()
        if item.url != nil {
            Button("Copy Link") { model.copyLink(item) }
            Button("Open on GitHub") { model.openOnGitHub(item) }
        }
    }
}
