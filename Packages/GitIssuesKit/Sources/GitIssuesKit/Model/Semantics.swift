import Foundation

/// What a status column means, inferred from its name, since GitHub only stores a free-form label.
public enum StatusCategory: Int, Sendable, Comparable {
    case backlog
    case unstarted
    case started
    case completed
    case canceled

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public static func infer(from name: String) -> StatusCategory {
        let n = name.lowercased()
        func has(_ words: String...) -> Bool { words.contains { n.contains($0) } }
        if has("cancel", "won't", "wont", "not planned", "duplicate", "rejected", "dropped", "abandon") { return .canceled }
        if has("done", "complete", "closed", "shipped", "released", "merged", "finished", "resolved", "live") { return .completed }
        if has("progress", "review", "doing", "wip", "testing", "blocked", "active") { return .started }
        if has("backlog", "icebox", "later", "someday", "triage", "inbox", "ideas", "no status") { return .backlog }
        if has("todo", "to do", "to-do", "open", "up next", "next", "ready", "planned", "new", "not started", "queued") { return .unstarted }
        return .started
    }

    public var isClosed: Bool { self == .completed || self == .canceled }

    /// The close reason GitHub should record when a card lands in a column of this kind.
    public var closeReason: String? {
        switch self {
        case .completed: "COMPLETED"
        case .canceled: "NOT_PLANNED"
        default: nil
        }
    }
}

public enum PriorityLevel: Int, Sendable, Comparable, CaseIterable {
    case none = 0
    case low
    case medium
    case high
    case urgent

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public static func infer(from name: String) -> PriorityLevel {
        let n = name.lowercased()
        func has(_ words: String...) -> Bool { words.contains { n.contains($0) } }
        if has("urgent", "critical", "blocker", "highest", "p0", "🔥") { return .urgent }
        if has("high", "p1", "major") { return .high }
        if has("medium", "normal", "p2", "mid") { return .medium }
        if has("low", "p3", "p4", "minor", "trivial") { return .low }
        return .medium
    }
}

extension FieldOption {
    public var statusCategory: StatusCategory { StatusCategory.infer(from: name) }
    public var priorityLevel: PriorityLevel { PriorityLevel.infer(from: name) }
}

/// The opinionated defaults offered for new projects and for projects without a Priority field.
public enum Defaults {
    public static let priorityOptions: [RemoteOption] = [
        RemoteOption(id: nil, name: "Urgent", color: "ORANGE"),
        RemoteOption(id: nil, name: "High", color: "RED"),
        RemoteOption(id: nil, name: "Medium", color: "YELLOW"),
        RemoteOption(id: nil, name: "Low", color: "GRAY"),
    ]

    public static let optionColors = ["GRAY", "BLUE", "GREEN", "YELLOW", "ORANGE", "RED", "PINK", "PURPLE"]
}
