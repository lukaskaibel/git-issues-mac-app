import AppKit
import GRDB
import SwiftUI

struct NewIssueDraft: Equatable {
    var projectId: String
    var repoId: String?
    var title = ""
    var body = ""
    var statusId: String?
    var priorityId: String?
    var assignees: [Person] = []
    var labels: [LabelRef] = []
    var parent: Item?
}

/// What the user can do to an issue. Each action becomes one or more queued mutations.
extension AppModel {
    // MARK: Status, priority, order

    private func statusMutations(_ item: Item, _ option: FieldOption?) -> [Mutation] {
        guard let fieldId = project(of: item)?.statusFieldId else { return [] }
        var result: [Mutation] = []
        if item.statusId != option?.id {
            result.append(.setField(.init(
                itemId: item.id, projectId: item.projectId, fieldId: fieldId, kind: .status,
                optionId: option?.id, base: item.statusId
            )))
        }
        // Keep GitHub's open/closed state in line with the column, so the issue reads right on github.com too.
        if item.kind == .issue, let contentId = item.contentId, let option {
            if let reason = option.statusCategory.closeReason {
                if !item.isClosed || item.stateReason != reason {
                    result.append(.setState(.init(contentId: contentId, closed: true, reason: reason)))
                }
            } else if item.isClosed {
                result.append(.setState(.init(contentId: contentId, closed: false, reason: nil)))
            }
        }
        return result
    }

    func setStatus(_ item: Item, to option: FieldOption?) {
        perform(statusMutations(item, option))
    }

    func setPriority(_ item: Item, to option: FieldOption?) {
        guard let fieldId = project(of: item)?.priorityFieldId, item.priorityId != option?.id else { return }
        perform([.setField(.init(
            itemId: item.id, projectId: item.projectId, fieldId: fieldId, kind: .priority,
            optionId: option?.id, base: item.priorityId
        ))])
    }

    /// Drops a card into a column at `index`, counted among the column's other cards.
    func drop(_ item: Item, in column: BoardColumn, at index: Int) {
        var mutations = statusMutations(item, column.option)
        let others = column.items.filter { $0.id != item.id }
        let target = min(max(index, 0), others.count)
        let unchanged = column.items.firstIndex { $0.id == item.id } == target
        if !unchanged, !others.isEmpty {
            let afterId: String?
            if target > 0 {
                afterId = others[target - 1].id
            } else {
                // To sit above the column's first card, go right behind whatever precedes that card in the project.
                let all = allItems.filter { $0.projectId == item.projectId && $0.id != item.id }
                let first = all.firstIndex { $0.id == others[0].id } ?? 0
                afterId = first > 0 ? all[first - 1].id : nil
            }
            mutations.append(.move(.init(itemId: item.id, projectId: item.projectId, afterItemId: afterId)))
        }
        perform(mutations)
    }

    // MARK: Content

    func rename(_ item: Item, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard item.isEditableContent, let contentId = item.contentId, !trimmed.isEmpty, trimmed != item.title else { return }
        perform([.setTitle(.init(itemId: item.id, contentId: contentId, value: trimmed, base: item.title))])
    }

    func setBody(_ item: Item, to body: String) {
        guard item.isEditableContent, let contentId = item.contentId, body != item.body else { return }
        perform([.setBody(.init(itemId: item.id, contentId: contentId, value: body, base: item.body))])
    }

    func toggleAssignee(_ item: Item, _ person: Person) {
        guard item.kind != .draft, let contentId = item.contentId else { return }
        let assigned = item.assignees.contains { $0.id == person.id }
        perform([.editAssignees(.init(contentId: contentId, add: assigned ? [] : [person], remove: assigned ? [person] : []))])
    }

    func toggleLabel(_ item: Item, _ label: LabelRef) {
        guard item.kind != .draft, let contentId = item.contentId else { return }
        let has = item.labels.contains { $0.id == label.id }
        perform([.editLabels(.init(contentId: contentId, add: has ? [] : [label], remove: has ? [label] : []))])
    }

    func addComment(to item: Item, body: String) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard item.kind != .draft, let contentId = item.contentId, let viewer, !trimmed.isEmpty else { return }
        perform([.addComment(.init(
            commentId: LocalID.make(), contentId: contentId, body: trimmed, author: viewer.person, createdAt: Date()
        ))])
    }

    func setClosed(_ sub: SubIssue, _ closed: Bool) {
        // A sub-issue that is on the board moves columns like any other card.
        if let item = item(contentId: sub.id) {
            let statuses = statusOptions(projectId: item.projectId)
            let wanted: StatusCategory = closed ? .completed : .unstarted
            if let option = statuses.first(where: { $0.statusCategory == wanted }) {
                setStatus(item, to: option)
                return
            }
        }
        perform([.setState(.init(contentId: sub.id, closed: closed, reason: closed ? "COMPLETED" : nil))])
    }

    @discardableResult
    func createIssue(_ draft: NewIssueDraft) -> String? {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              let project = projects.first(where: { $0.id == draft.projectId }),
              let repo = repos(projectId: draft.projectId).first(where: { $0.id == draft.repoId }) else { return nil }
        let itemId = LocalID.make()
        UserDefaults.standard.set(repo.id, forKey: "lastRepo.\(project.id)")
        perform([.createIssue(.init(
            itemId: itemId, contentId: LocalID.make(), projectId: project.id, repoId: repo.id, repo: repo.nameWithOwner,
            title: title, body: draft.body,
            statusFieldId: project.statusFieldId, statusId: draft.statusId,
            priorityFieldId: project.priorityFieldId, priorityId: draft.priorityId,
            assignees: draft.assignees, labels: draft.labels,
            parentContentId: draft.parent?.contentId, parentNumber: draft.parent?.number, parentTitle: draft.parent?.title,
            author: viewer?.login, createdAt: Date()
        ))])
        return itemId
    }

    func defaultRepoId(projectId: String) -> String? {
        let available = repos(projectId: projectId)
        let last = UserDefaults.standard.string(forKey: "lastRepo.\(projectId)")
        if let last, available.contains(where: { $0.id == last }) { return last }
        // Otherwise the repository most cards on this board come from.
        let counts = Dictionary(grouping: allItems.filter { $0.projectId == projectId }.compactMap(\.repoId)) { $0 }.mapValues(\.count)
        return counts.max { $0.value < $1.value }?.key ?? available.first?.id
    }

    // MARK: Columns

    /// Saves a new set of status columns. Shown at once; rolled back if GitHub refuses.
    func saveColumns(projectId: String, _ newOptions: [RemoteOption]) {
        guard let fieldId = projects.first(where: { $0.id == projectId })?.statusFieldId else { return }
        do {
            try db.writer.write { db in
                try FieldOption.filter(Column("projectId") == projectId && Column("fieldId") == fieldId).deleteAll(db)
                for (index, option) in newOptions.enumerated() {
                    try FieldOption(
                        id: option.id ?? LocalID.make(), fieldId: fieldId, projectId: projectId, kind: .status,
                        name: option.name, color: option.color, descr: option.descr, position: index
                    ).insert(db)
                }
            }
        } catch {
            return
        }
        reloadNow()
        Task {
            do {
                try await engine.updateOptions(projectId: projectId, fieldId: fieldId, kind: .status, options: newOptions)
            } catch {
                status.post(Notice(
                    title: "Columns could not be saved",
                    message: "Changing columns needs a connection to GitHub. \(error.localizedDescription)",
                    isWarning: true
                ))
                await engine.forceRefresh()
            }
        }
    }

    // MARK: List section order

    private var listOrderKey: String? {
        switch scope {
        case .project(let id): "listOrder.\(id)"
        case .myIssues: "listOrder.mine"
        case nil: nil
        }
    }

    /// The order the list's sections were dragged into, if they were. This is a preference of this Mac
    /// and does not change the project on GitHub; the board's column order does.
    var customListOrder: [String] {
        listOrderKey.flatMap { UserDefaults.standard.stringArray(forKey: $0) } ?? []
    }

    /// Moves a list section in front of another one (or to the end).
    func moveListSection(_ id: String, before target: String?) {
        guard let key = listOrderKey, id != target else { return }
        var order = sections.map(\.id)
        // Sections that are currently empty keep their remembered place after the visible ones.
        order += customListOrder.filter { !order.contains($0) }
        order.removeAll { $0 == id }
        if let target, let index = order.firstIndex(of: target) {
            order.insert(id, at: index)
        } else {
            order.insert(id, at: sections.filter { $0.id != id }.count)
        }
        UserDefaults.standard.set(order, forKey: key)
        reloadNow()
    }

    func addPriorityField(projectId: String) {
        Task {
            do {
                try await engine.createPriorityField(projectId: projectId)
            } catch {
                status.post(Notice(title: "Priority could not be added", message: error.localizedDescription, isWarning: true))
            }
        }
    }

    // MARK: Leaving the app

    func openOnGitHub(_ item: Item) {
        if let url = item.url.flatMap(URL.init(string:)) { NSWorkspace.shared.open(url) }
    }

    func copyLink(_ item: Item) {
        guard let url = item.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        status.post(Notice(title: "Link copied", message: "\(item.displayNumber) \(item.title)"))
    }

    func apply(_ action: Notice.Action) {
        switch action {
        case .applyField(let mutation, _):
            perform([.setField(mutation)])
        case .openItem(let id):
            if let item = allItems.first(where: { $0.id == id }) { open(item) }
        }
    }
}
