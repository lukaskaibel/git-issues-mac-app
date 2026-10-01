#if DEBUG
import AppKit
import SwiftUI

/// Development-only remote control. Launch with `-debugCommandFile <path>` and append lines to that file
/// to drive the app (open an issue, run a drag, go offline) so states can be checked without a mouse.
@MainActor
enum DebugRemote {
    private static var processed = 0
    private static var timer: Timer?
    private static var dragTimer: Timer?
    private static var scrollTimer: Timer?
    private static var activity: NSObjectProtocol?

    static func startIfRequested(model: AppModel) {
        guard let path = UserDefaults.standard.string(forKey: "debugCommandFile") else { return }
        // Keep timers running at full rate while the window is in the background.
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Debug remote")
        processed = (try? String(contentsOfFile: path, encoding: .utf8))?.split(separator: "\n").count ?? 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
                let lines = text.split(separator: "\n").map(String.init)
                while processed < lines.count {
                    run(lines[processed], model: model)
                    processed += 1
                }
            }
        }
    }

    static func log(_ text: String) {
        guard let path = UserDefaults.standard.string(forKey: "debugCommandFile") else { return }
        let url = URL(fileURLWithPath: path + ".log")
        let line = Data((text + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: url)
        }
    }

    private static func item(_ token: String, _ model: AppModel) -> Item? {
        guard let number = Int(token) else { return nil }
        return model.scopedItems.first { $0.number == number } ?? model.allItems.first { $0.number == number }
    }

    /// The only project test commands may change.
    static let sandboxTitle = "Git Issues Sandbox"

    private static func run(_ line: String, model: AppModel) {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        let argument = parts.count > 1 ? parts[1] : ""
        let readOnly: Set<String> = ["select", "dump", "notice", "mode", "open", "close", "focus", "scrolltest", "appearance", "icon", "settings", "back", "forward", "wait"]
        if let command = parts.first, !readOnly.contains(command), model.currentProject?.title != sandboxTitle {
            log("refused \"\(line)\": the open project is not the sandbox")
            return
        }
        switch parts.first {
        case "select":
            if argument == "mine" {
                model.select(.myIssues)
            } else if let project = model.projects.first(where: { $0.title.localizedCaseInsensitiveContains(argument) }) {
                model.select(.project(project.id))
            }
        case "mode":
            model.closeDetail()
            withAnimation(Theme.spring) { model.viewMode = argument == "list" ? .list : .board }
        case "open":
            if let item = item(argument, model) { model.open(item) }
        case "close":
            model.closeDetail()
        case "focus":
            model.focusedItemId = item(argument, model)?.id
        case "overlay":
            switch argument {
            case "palette": model.overlay = .palette(.root)
            case "new": model.overlay = .newIssue(statusId: nil, parentItemId: nil)
            default: model.overlay = nil
            }
        case "key":
            sendKeys(argument)
        case "keycode":
            // keycode <code> [cmd]
            let bits = argument.split(separator: " ").map(String.init)
            if let code = bits.first.flatMap({ UInt16($0) }) {
                sendKey(characters: code == 36 ? "\r" : "", code: code, modifiers: bits.contains("cmd") ? .command : [])
            }
        case "status":
            let bits = argument.split(separator: " ", maxSplits: 1).map(String.init)
            if bits.count == 2, let item = item(bits[0], model),
               let option = model.statusOptions(projectId: item.projectId).first(where: { $0.name.caseInsensitiveCompare(bits[1]) == .orderedSame }) {
                withAnimation(Theme.spring) { model.setStatus(item, to: option) }
            }
        case "offline":
            GraphQLClient.simulateOffline.withLock { $0 = argument == "on" }
            model.refresh()
        case "drag":
            // drag <number> <row index> <hold|drop> <column name>
            let bits = argument.split(separator: " ", maxSplits: 3).map(String.init)
            if bits.count == 4, let item = item(bits[0], model), let index = Int(bits[1]) {
                drag(item, toColumn: bits[3], index: index, hold: bits[2] == "hold", model: model)
            }
        case "dragcolumn":
            // dragcolumn <hold|drop> <columns to move, e.g. -2> <column name>
            let bits = argument.split(separator: " ", maxSplits: 2).map(String.init)
            if bits.count == 3, let steps = Double(bits[1]),
               let column = model.columns.first(where: { $0.title.caseInsensitiveCompare(bits[2]) == .orderedSame }),
               let frame = model.boardDrag.columnFrames[column.id] {
                let step = frame.width + 12
                var tick = 0
                dragTimer?.invalidate()
                dragTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { timer in
                    MainActor.assumeIsolated {
                        tick += 1
                        let t = min(Double(tick) / 30, 1)
                        model.boardDrag.dragColumn(column, translation: CGFloat(steps * t) * step * 0.92, step: step, model: model)
                        if tick >= 30 {
                            timer.invalidate()
                            if bits[0] == "drop" { model.boardDrag.dropColumn(model: model) }
                        }
                    }
                }
            }
        case "dropcolumn":
            model.boardDrag.dropColumn(model: model)
        case "movesection":
            // movesection <section title> before <section title|end>
            let bits = argument.components(separatedBy: " before ")
            if bits.count == 2, let moving = model.sections.first(where: { $0.title == bits[0] }) {
                model.moveListSection(moving.id, before: model.sections.first { $0.title == bits[1] }?.id)
            }
        case "drop":
            model.boardDrag.ended(model: model)
        case "canceldrag":
            model.dragCancelToken += 1
        case "appearance":
            if let setting = AppearanceSetting(rawValue: argument) { model.appearance = setting }
        case "icon":
            if let choice = AppIconChoice(rawValue: argument) { model.appIcon = choice }
        case "settings":
            model.settingsRequest += 1
        case "back":
            model.goBack()
        case "forward":
            model.goForward()
        case "scrolltest":
            scrollTest(label: argument)
        case "dump":
            let drag = model.boardDrag
            log("active=\(drag.active.map { "\($0.item.displayNumber) loc=\($0.location) lifted=\($0.lifted) settling=\($0.settling)" } ?? "nil") target=\(String(describing: drag.target))")
            for column in model.columns {
                log("  column \(column.title) frame=\(drag.columnFrames[column.id].map { "\($0)" } ?? "nil") cards=\(column.items.compactMap { item in drag.cardFrames[item.id].map { "\(item.displayNumber):\(Int($0.minX)),\(Int($0.minY))" } }.joined(separator: " "))")
            }
            log("  project=\(model.currentProject?.title ?? "-") mode=\(model.viewMode.rawValue)")
            log("  columns=\(model.columns.map(\.title).joined(separator: " | ")) sections=\(model.sections.map(\.title).joined(separator: " | ")) columnDrag=\(String(describing: drag.column))")
            log("  overlay=\(String(describing: model.overlay)) open=\(model.openItem?.displayNumber ?? "-") focus=\(model.targetItem?.displayNumber ?? "-") phase=\(model.status.phase) pending=\(model.pendingCount)")
        case "column":
            // column add <name> | column delete <name> | column rename <old>=<new>
            guard let projectId = model.currentProjectId else { break }
            var options = model.statusOptions(projectId: projectId).map(\.remote)
            let bits = argument.split(separator: " ", maxSplits: 1).map(String.init)
            guard bits.count == 2 else { break }
            switch bits[0] {
            case "add": options.append(RemoteOption(id: nil, name: bits[1], color: "PINK"))
            case "delete": options.removeAll { $0.name == bits[1] }
            case "rename":
                let names = bits[1].split(separator: "=").map(String.init)
                if names.count == 2, let index = options.firstIndex(where: { $0.name == names[0] }) { options[index].name = names[1] }
            default: break
            }
            withAnimation(Theme.spring) { model.saveColumns(projectId: projectId, options) }
        case "body":
            if let item = model.openItem { model.setBody(item, to: argument.replacingOccurrences(of: "\\n", with: "\n")) }
        case "comment":
            if let item = model.openItem { model.addComment(to: item, body: argument) }
        case "notice":
            model.status.post(Notice(title: "Test notice", message: argument))
        default:
            break
        }
    }

    /// Moves a card along a straight path with eased timing, the way a hand would.
    private static func drag(_ item: Item, toColumn name: String, index: Int, hold: Bool, model: AppModel) {
        let drag = model.boardDrag
        guard let from = drag.cardFrames[item.id],
              let column = model.columns.first(where: { $0.title.caseInsensitiveCompare(name) == .orderedSame }),
              let columnFrame = drag.columnFrames[column.id] else { return }
        let others = column.items.filter { $0.id != item.id }
        var y = columnFrame.minY + 40 + from.height / 2
        if index < others.count, let frame = drag.cardFrames[others[index].id] {
            y = frame.minY + 6
        } else if let last = others.last, let frame = drag.cardFrames[last.id] {
            y = frame.maxY + from.height / 2
        }
        let start = CGPoint(x: from.midX, y: from.midY)
        let end = CGPoint(x: columnFrame.midX, y: y)
        log("drag \(item.displayNumber) from \(start) to \(end) column=\(columnFrame)")
        var step = 0
        let steps = 36
        var previous = start
        dragTimer?.invalidate()
        dragTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { timer in
            MainActor.assumeIsolated {
                step += 1
                let t = min(Double(step) / Double(steps), 1)
                let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
                let point = CGPoint(x: start.x + (end.x - start.x) * eased, y: start.y + (end.y - start.y) * eased)
                let velocity = CGSize(width: (point.x - previous.x) * 60, height: (point.y - previous.y) * 60)
                previous = point
                drag.changed(location: point, start: start, velocity: velocity, model: model)
                if step >= steps {
                    timer.invalidate()
                    if !hold { drag.ended(model: model) }
                }
            }
        }
    }

    /// Scrolls the tallest scroll view top to bottom in fixed steps and reports how long each step
    /// keeps the main thread busy. A step over 8 ms would drop a frame on a 120 Hz display.
    private static func scrollTest(label: String) {
        guard let root = NSApp.windows.first(where: { $0.isVisible })?.contentView else { return }
        var views: [NSScrollView] = []
        func collect(_ view: NSView) {
            if let scroll = view as? NSScrollView { views.append(scroll) }
            view.subviews.forEach(collect)
        }
        collect(root)
        guard let scrollView = views.max(by: { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }),
              let document = scrollView.documentView else {
            log("scrolltest: no scroll view")
            return
        }
        let clip = scrollView.contentView
        var times: [Double] = []
        var y: CGFloat = 0
        let step: CGFloat = 40
        var steps = 0
        scrollTimer?.invalidate()
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { timer in
            MainActor.assumeIsolated {
                let limit = max(0, document.frame.height - clip.bounds.height)
                let start = CACurrentMediaTime()
                y = min(y + step, limit)
                clip.scroll(to: NSPoint(x: 0, y: y))
                scrollView.reflectScrolledClipView(clip)
                root.layoutSubtreeIfNeeded()
                root.displayIfNeeded()
                CATransaction.flush()
                times.append((CACurrentMediaTime() - start) * 1000)
                steps += 1
                if y >= limit || steps > 600 {
                    timer.invalidate()
                    let sorted = times.sorted()
                    let average = times.reduce(0, +) / Double(max(times.count, 1))
                    let p95 = sorted.isEmpty ? 0 : sorted[Int(Double(sorted.count - 1) * 0.95)]
                    log(String(
                        format: "scrolltest %@: %d steps over %.0f pt, avg %.1f ms, p95 %.1f ms, max %.1f ms, over 8 ms: %d, over 16 ms: %d",
                        label, times.count, limit, average, p95, sorted.last ?? 0,
                        times.filter { $0 > 8 }.count, times.filter { $0 > 16 }.count
                    ))
                }
            }
        }
    }

    private static func sendKeys(_ text: String) {
        for character in text {
            sendKey(characters: String(character), code: 0)
        }
    }

    private static func sendKey(characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = []) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
        if let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code
        ) {
            NSApp.sendEvent(event)
        }
    }
}
#endif
