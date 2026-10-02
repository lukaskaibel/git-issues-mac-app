import SwiftUI

/// One row of a picker: a status, a priority, a person or a label.
struct PickerItem: Identifiable {
    var id: String
    var title: String
    var subtitle: String?
    var selected = false
    var icon: AnyView
    var shortcut: String?
}

/// A searchable list driven entirely from the keyboard: type to filter, arrows to move, Return to pick.
struct PickerList: View {
    var placeholder: String
    var items: [PickerItem]
    /// Multi-select pickers stay open after a pick.
    var staysOpen = false
    var width: CGFloat = 260
    var maxRows = 9
    var fieldFont: Font = .ui
    var onPick: (String) -> Void
    var onClose: () -> Void

    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool

    var body: some View {
        let visible = filtered
        VStack(spacing: 0) {
            TextField(placeholder, text: $query)
                .textFieldStyle(.plain)
                .font(fieldFont)
                .focused($focused)
                .focusOnAppear()
                .padding(.horizontal, 12)
                .frame(height: 36)
                .onKeyPress(.downArrow) {
                    index = min(index + 1, max(visible.count - 1, 0))
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    index = max(index - 1, 0)
                    return .handled
                }
                .onKeyPress(.escape) {
                    onClose()
                    return .handled
                }
                .onKeyPress(phases: .down) { press in
                    // Number keys pick directly while nothing has been typed.
                    guard query.isEmpty, let item = items.first(where: { $0.shortcut == press.characters }) else { return .ignored }
                    pick(item)
                    return .handled
                }
                .onSubmit {
                    if visible.indices.contains(index) { pick(visible[index]) }
                }
            Rectangle().fill(Theme.popoverBorder).frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(visible.enumerated()), id: \.element.id) { position, item in
                            PickerRow(item: item, active: position == index)
                                .id(item.id)
                                .onTapGesture { pick(item) }
                                .onHover { if $0 { index = position } }
                        }
                        if visible.isEmpty {
                            Text("No matches")
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.never)
                .frame(height: min(CGFloat(max(visible.count, 1)), CGFloat(maxRows)) * 32 + 8)
                .onChange(of: index) {
                    if visible.indices.contains(index) { proxy.scrollTo(visible[index].id) }
                }
            }
        }
        .frame(width: width)
        .font(.ui)
        .foregroundStyle(Theme.text)
        .onAppear {
            focused = true
            // Single-choice pickers start on the current value, so Return keeps it.
            if !staysOpen, let current = items.firstIndex(where: \.selected) { index = current }
        }
        .onChange(of: query) { index = 0 }
    }

    private var filtered: [PickerItem] {
        guard !query.isEmpty else { return items }
        return items
            .compactMap { item -> (PickerItem, Int)? in
                let score = max(fuzzyScore(query, item.title) ?? -1, item.subtitle.flatMap { fuzzyScore(query, $0) } ?? -1)
                return score >= 0 ? (item, score) : nil
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private func pick(_ item: PickerItem) {
        onPick(item.id)
        if !staysOpen { onClose() }
    }
}

struct PickerRow: View {
    var item: PickerItem
    var active: Bool

    var body: some View {
        HStack(spacing: 10) {
            item.icon.frame(width: 18, height: 18)
            Text(item.title).lineLimit(1)
            if let subtitle = item.subtitle {
                Text(subtitle).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if item.selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textBody)
            }
            if let shortcut = item.shortcut {
                Keycap(shortcut, emphasized: active)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(active ? Theme.popoverSelected : .clear))
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }
}

/// Subsequence match: every character of the query appears in order. Higher is better; nil is no match.
func fuzzyScore(_ query: String, _ text: String) -> Int? {
    let q = Array(query.lowercased().filter { !$0.isWhitespace })
    guard !q.isEmpty else { return 0 }
    let t = Array(text.lowercased())
    var score = 0
    var qi = 0
    var streak = 0
    for (ti, character) in t.enumerated() where qi < q.count {
        if character == q[qi] {
            streak += 1
            score += 2 + streak * 2
            if ti == 0 || !t[ti - 1].isLetter && !t[ti - 1].isNumber { score += 6 }
            qi += 1
        } else {
            streak = 0
        }
    }
    guard qi == q.count else { return nil }
    return score - t.count / 8
}

// MARK: - Picker contents for an issue

enum PickerKind: Equatable {
    case status
    case priority
    case assignees
    case labels
}

extension AppModel {
    func pickerItems(_ kind: PickerKind, for item: Item) -> [PickerItem] {
        switch kind {
        case .status:
            return statusOptions(projectId: item.projectId).enumerated().map { index, option in
                PickerItem(
                    id: option.id, title: option.name, selected: item.statusId == option.id,
                    icon: AnyView(StatusIcon(glyph: glyph(projectId: item.projectId, optionId: option.id))),
                    shortcut: index < 9 ? "\(index + 1)" : nil
                )
            }
        case .priority:
            let none = PickerItem(
                id: "", title: "No priority", selected: item.priorityId == nil,
                icon: AnyView(PriorityIcon(level: .none)), shortcut: "0"
            )
            return [none] + priorityOptions(projectId: item.projectId).enumerated().map { index, option in
                PickerItem(
                    id: option.id, title: option.name, selected: item.priorityId == option.id,
                    icon: AnyView(PriorityIcon(level: option.priorityLevel)),
                    shortcut: index < 9 ? "\(index + 1)" : nil
                )
            }
        case .assignees:
            return people(for: item).map { person in
                PickerItem(
                    id: person.id, title: person.login, subtitle: person.name,
                    selected: item.assignees.contains { $0.id == person.id },
                    icon: AnyView(Avatar(login: person.login, url: person.avatarUrl, size: 18))
                )
            }
        case .labels:
            return labels(for: item).map { label in
                PickerItem(
                    id: label.id, title: label.name,
                    selected: item.labels.contains { $0.id == label.id },
                    icon: AnyView(Circle().fill(Theme.labelColor(label.color)).frame(width: 9, height: 9))
                )
            }
        }
    }

    func pick(_ kind: PickerKind, id: String, for item: Item) {
        // Work with the latest copy: multi-select pickers stay open across several picks.
        let current = allItems.first { $0.id == item.id } ?? item
        switch kind {
        case .status:
            if let option = statusOptions(projectId: current.projectId).first(where: { $0.id == id }) {
                withAnimation(Theme.spring) { setStatus(current, to: option) }
            }
        case .priority:
            setPriority(current, to: priorityOptions(projectId: current.projectId).first { $0.id == id })
        case .assignees:
            if let person = people(for: current).first(where: { $0.id == id }) { toggleAssignee(current, person) }
        case .labels:
            if let label = labels(for: current).first(where: { $0.id == id }) { toggleLabel(current, label) }
        }
    }

    /// People who can be assigned: the repository's assignable users, or everyone seen on the board until those load.
    func people(for item: Item) -> [Person] {
        people(projectId: item.projectId, repoId: item.repoId)
    }

    func people(projectId: String, repoId: String?) -> [Person] {
        var result = repos.first { $0.projectId == projectId && $0.id == repoId }?.assignableUsers ?? []
        if result.isEmpty {
            var seen = Set<String>()
            result = allItems.filter { $0.projectId == projectId }.flatMap(\.assignees).filter { seen.insert($0.id).inserted }
            if let viewer, seen.insert(viewer.id).inserted { result.append(viewer.person) }
        }
        let me = viewer?.id
        return result.sorted { a, b in
            if (a.id == me) != (b.id == me) { return a.id == me }
            return a.login.localizedCaseInsensitiveCompare(b.login) == .orderedAscending
        }
    }

    func labels(for item: Item) -> [LabelRef] {
        labels(projectId: item.projectId, repoId: item.repoId)
    }

    func labels(projectId: String, repoId: String?) -> [LabelRef] {
        let result = repos.first { $0.projectId == projectId && $0.id == repoId }?.labels ?? []
        if !result.isEmpty { return result }
        var seen = Set<String>()
        return allItems
            .filter { $0.projectId == projectId && $0.repoId == repoId }
            .flatMap(\.labels)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// A property value that opens its picker in a popover when clicked.
struct PropertyButton<Label: View>: View {
    @Environment(AppModel.self) private var model
    var kind: PickerKind
    var item: Item
    @ViewBuilder var label: Label

    @State private var open = false

    var body: some View {
        Button {
            open = true
        } label: {
            label
                .padding(.horizontal, 8)
                .frame(minHeight: 28)
                .hoverFill(active: open)
        }
        .buttonStyle(PlainPressStyle())
        .popover(isPresented: $open, arrowEdge: .leading) {
            PickerList(
                placeholder: placeholder,
                items: model.pickerItems(kind, for: model.allItems.first { $0.id == item.id } ?? item),
                staysOpen: kind == .assignees || kind == .labels,
                onPick: { model.pick(kind, id: $0, for: item) },
                onClose: { open = false }
            )
            .background(Theme.popover)
        }
    }

    private var placeholder: String {
        switch kind {
        case .status: "Change status…"
        case .priority: "Set priority…"
        case .assignees: "Assign to…"
        case .labels: "Add labels…"
        }
    }
}
