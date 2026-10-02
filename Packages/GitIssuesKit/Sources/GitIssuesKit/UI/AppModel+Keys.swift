import AppKit
import SwiftUI

/// Single-key shortcuts, Linear style. They act on the open issue, or else on the card or row under
/// the pointer or keyboard focus, and stay out of the way while typing.
extension AppModel {
    /// The issue shortcuts and palette commands apply to.
    var targetItem: Item? {
        if let openItem { return openItem }
        guard let id = hoveredItemId ?? focusedItemId else { return nil }
        return scopedItems.first { $0.id == id }
    }

    enum PointerEvent {
        case entered
        case left
    }

    /// Cards and rows report the pointer here. The pointer takes over from the keyboard focus, and
    /// nothing observable changes unless there was a keyboard focus to clear.
    func pointer(_ event: PointerEvent, _ id: String) {
        switch event {
        case .entered:
            guard !isDragging else { return }
            hoveredItemId = id
            if focusedItemId != nil { focusedItemId = nil }
        case .left:
            if hoveredItemId == id { hoveredItemId = nil }
        }
    }

    /// The issue keyboard navigation starts from.
    private var cursorId: String? { focusedItemId ?? hoveredItemId }

    private func moveFocus(to id: String) {
        hoveredItemId = nil
        focusedItemId = id
        focusScrollToken += 1
    }

    /// Issues in the order they read on screen, for stepping with J/K and the arrow buttons.
    var orderedItems: [Item] {
        if openItem == nil, viewMode == .board, currentProjectId != nil {
            return columns.flatMap(\.items)
        }
        return sections.flatMap(\.items)
    }

    func position(of item: Item) -> (index: Int, count: Int)? {
        let items = sections.flatMap(\.items)
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return nil }
        return (index, items.count)
    }

    /// Moves to the next or previous issue: opens it when an issue is open, otherwise moves the focus.
    func step(_ delta: Int) {
        let items = openItem != nil ? sections.flatMap(\.items) : orderedItems
        guard !items.isEmpty else { return }
        let currentId = openItemId ?? cursorId
        let next: Item
        if let index = items.firstIndex(where: { $0.id == currentId }) {
            next = items[min(max(index + delta, 0), items.count - 1)]
        } else {
            next = delta > 0 ? items[0] : items[items.count - 1]
        }
        if openItem != nil {
            open(next)
        } else {
            moveFocus(to: next.id)
        }
    }

    /// On the board: left and right jump to the neighbouring column, keeping the row where possible.
    private func stepColumn(_ delta: Int) {
        guard viewMode == .board, openItem == nil else { return }
        let filled = columns.filter { !$0.items.isEmpty }
        guard !filled.isEmpty else { return }
        let current = cursorId
        guard let columnIndex = filled.firstIndex(where: { column in column.items.contains { $0.id == current } }),
              let row = filled[columnIndex].items.firstIndex(where: { $0.id == current }) else {
            moveFocus(to: filled[0].items[0].id)
            return
        }
        let target = filled[min(max(columnIndex + delta, 0), filled.count - 1)]
        moveFocus(to: target.items[min(row, target.items.count - 1)].id)
    }

    private func stepWithinColumn(_ delta: Int) {
        let current = cursorId
        guard let column = columns.first(where: { column in column.items.contains { $0.id == current } }),
              let row = column.items.firstIndex(where: { $0.id == current }) else {
            step(delta)
            return
        }
        moveFocus(to: column.items[min(max(row + delta, 0), column.items.count - 1)].id)
    }

    /// How long after a dialog opens keystrokes are held for its text field.
    static let typeAheadWindow: TimeInterval = 0.5

    private func hold(_ event: NSEvent) {
        heldKeys.append(event)
        guard heldKeysTimer == nil else { return }
        let timer = Timer(timeInterval: 0.01, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else {
                    timer.invalidate()
                    return
                }
                let fieldHasFocus = NSApp.keyWindow?.firstResponder is NSTextView
                let expired = self.overlayOpenedAt.map { Date().timeIntervalSince($0) >= Self.typeAheadWindow } ?? true
                guard fieldHasFocus || expired || self.overlay == nil else { return }
                timer.invalidate()
                self.heldKeysTimer = nil
                let events = self.heldKeys
                self.heldKeys = []
                // Sent again in order; now that the field has focus they go straight to it.
                for event in events { NSApp.sendEvent(event) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        heldKeysTimer = timer
    }

    func installKeyMonitor() {
        guard keyMonitorToken == nil else { return }
        keyMonitorToken = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let handled = MainActor.assumeIsolated { self.handle(event) }
            return handled ? nil : event
        }
    }

    /// Returns true when the key was used.
    private func handle(_ event: NSEvent) -> Bool {
        guard signedIn else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control])
        let isEscape = event.keyCode == 53

        if isDragging {
            if isEscape {
                dragCancelToken += 1
                return true
            }
            return false
        }
        // Overlays and text fields handle their own keys. A dialog's text field only takes focus once the
        // dialog is on screen, so typing that starts right away is held and handed over when it can land.
        if overlay != nil {
            let fieldHasFocus = NSApp.keyWindow?.firstResponder is NSTextView
            let justOpened = overlayOpenedAt.map { Date().timeIntervalSince($0) < Self.typeAheadWindow } ?? false
            if !heldKeys.isEmpty || (!fieldHasFocus && justOpened && modifiers.isEmpty && !isEscape) {
                hold(event)
                return true
            }
            return false
        }
        if let responder = NSApp.keyWindow?.firstResponder, responder is NSTextView { return false }
        guard modifiers.isEmpty else { return false }

        if isEscape {
            if openItem != nil {
                closeDetail()
                return true
            }
            return false
        }

        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        // Two-key "go to" sequences: G then B, L, M or P.
        if let started = pendingGoTo, Date().timeIntervalSince(started) < 1.2 {
            pendingGoTo = nil
            switch key {
            case "b":
                if currentProjectId != nil {
                    closeDetail()
                    withAnimation(Theme.spring) { viewMode = .board }
                }
                return true
            case "l":
                closeDetail()
                withAnimation(Theme.spring) { viewMode = .list }
                return true
            case "m":
                select(.myIssues)
                return true
            case "p":
                overlay = .palette(.projects)
                return true
            default:
                break
            }
        }

        switch event.keyCode {
        case 125: // down
            if viewMode == .board, openItem == nil, currentProjectId != nil { stepWithinColumn(1) } else { step(1) }
            return true
        case 126: // up
            if viewMode == .board, openItem == nil, currentProjectId != nil { stepWithinColumn(-1) } else { step(-1) }
            return true
        case 123: // left
            stepColumn(-1)
            return viewMode == .board && openItem == nil
        case 124: // right
            stepColumn(1)
            return viewMode == .board && openItem == nil
        case 36: // return
            if openItem == nil, let item = targetItem {
                open(item)
                return true
            }
            return false
        default:
            break
        }

        switch key {
        case "g":
            pendingGoTo = Date()
            return true
        case "c":
            guard currentProjectId != nil || !projects.isEmpty else { return false }
            overlay = .newIssue(statusId: nil, parentItemId: nil)
            return true
        case "/":
            overlay = .palette(.root)
            return true
        case "j":
            step(1)
            return true
        case "k":
            step(-1)
            return true
        default:
            break
        }

        guard let item = targetItem else { return false }
        switch key {
        case "s":
            overlay = .palette(.status(itemId: item.id))
        case "p":
            guard project(of: item)?.priorityFieldId != nil else { return false }
            overlay = .palette(.priority(itemId: item.id))
        case "a":
            guard item.kind != .draft else { return false }
            overlay = .palette(.assignees(itemId: item.id))
        case "l":
            guard item.kind != .draft else { return false }
            overlay = .palette(.labels(itemId: item.id))
        case "i":
            guard item.kind != .draft, let viewer else { return false }
            toggleAssignee(item, viewer.person)
        default:
            return false
        }
        return true
    }
}
