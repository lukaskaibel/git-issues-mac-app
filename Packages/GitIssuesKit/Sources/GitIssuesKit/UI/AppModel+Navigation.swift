import AppKit
import SwiftUI

/// One place in the app: which project or view, shown as board or list, and which issue is open.
struct Location: Equatable {
    var scope: Scope?
    var viewMode: ViewMode
    var itemId: String?
}

enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    @MainActor
    func apply() {
        switch self {
        case .system: NSApplication.shared.appearance = nil
        case .light: NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark: NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

/// The icons the app can wear in the Dock. The first one is also the icon of the app bundle.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case e, g, f, k, i, j

    var id: String { rawValue }

    var title: String {
        switch self {
        case .e: "Board"
        case .g: "Board on colour"
        case .f: "Board, dark"
        case .k: "Two columns"
        case .i: "Three bars"
        case .j: "Checklist"
        }
    }

    var image: NSImage? {
        Bundle.module.image(forResource: "icon-\(rawValue.uppercased())")
    }

    @MainActor
    func apply() {
        // The default is the bundle's own icon; setting nil hands the Dock back to it.
        NSApplication.shared.applicationIconImage = self == .e ? nil : image
    }
}

/// Back and forward through the places visited, the way a browser does it.
extension AppModel {
    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex >= 0 && historyIndex < history.count - 1 }

    /// Notes the current place after the user went somewhere. Anything ahead in the history is dropped.
    func recordNavigation() {
        guard !isRestoringLocation, scope != nil else { return }
        let current = Location(scope: scope, viewMode: viewMode, itemId: openItemId)
        if historyIndex >= 0, history.indices.contains(historyIndex), history[historyIndex] == current { return }
        if historyIndex < history.count - 1 {
            history.removeSubrange((historyIndex + 1)...)
        }
        history.append(current)
        if history.count > 200 { history.removeFirst(history.count - 200) }
        historyIndex = history.count - 1
    }

    func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        restore(history[historyIndex])
    }

    func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        restore(history[historyIndex])
    }

    private func restore(_ location: Location) {
        isRestoringLocation = true
        defer { isRestoringLocation = false }
        overlay = nil
        if let target = location.scope, target != scope {
            select(target)
        }
        if viewMode != location.viewMode {
            withAnimation(Theme.spring) { viewMode = location.viewMode }
        }
        if let id = location.itemId, let item = allItems.first(where: { $0.id == id }) {
            if openItemId != id { open(item) }
        } else {
            closeDetail()
        }
    }

    // MARK: Mouse buttons and trackpad swipes

    func installNavigationMonitors() {
        // Buttons 3 and 4 are the "back" and "forward" side buttons on most mice.
        NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            guard let self, event.buttonNumber == 3 || event.buttonNumber == 4 else { return event }
            let number = event.buttonNumber
            return MainActor.assumeIsolated {
                guard self.signedIn else { return event }
                if number == 3 { self.goBack() } else { self.goForward() }
                return nil
            }
        }
        // Three-finger swipe, when "Swipe between pages" is set to three fingers.
        NSEvent.addLocalMonitorForEvents(matching: .swipe) { [weak self] event in
            guard let self, event.deltaX != 0 else { return event }
            let back = event.deltaX > 0
            return MainActor.assumeIsolated {
                guard self.signedIn else { return event }
                if back { self.goBack() } else { self.goForward() }
                return nil
            }
        }
        // Two-finger swipe, as in Safari.
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated { self.trackSwipe(event) ? nil : event }
        }
    }

    /// Starts following a horizontal two-finger swipe if it should navigate rather than scroll.
    private func trackSwipe(_ event: NSEvent) -> Bool {
        guard signedIn, overlay == nil, swipeProgress == 0,
              NSEvent.isSwipeTrackingFromScrollEventsEnabled,
              event.phase == .began,
              abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return false }
        let wantsBack = event.scrollingDeltaX > 0
        guard wantsBack ? canGoBack : canGoForward else { return false }
        // On the board a sideways swipe scrolls the columns; it only navigates once the board is at its edge.
        if openItem == nil, viewMode == .board, currentProjectId != nil {
            let atEdge = wantsBack ? boardDrag.scrollX <= 0.5 : boardDrag.scrollX >= boardDrag.maxScrollX - 0.5
            if !atEdge { return false }
        }
        event.trackSwipeEvent(
            options: [.lockDirection, .clampGestureAmount],
            dampenAmountThresholdMin: canGoForward ? -1 : 0,
            max: canGoBack ? 1 : 0
        ) { [weak self] amount, phase, isComplete, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if phase == .ended {
                    if amount > 0 { self.goBack() } else if amount < 0 { self.goForward() }
                }
                if isComplete || phase == .ended || phase == .cancelled {
                    withAnimation(Theme.quick) { self.swipeProgress = 0 }
                } else {
                    self.swipeProgress = Double(amount)
                }
            }
        }
        return true
    }
}
