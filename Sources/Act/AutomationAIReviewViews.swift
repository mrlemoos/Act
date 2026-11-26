import ActCore
import AppKit
import SwiftUI

struct AIInlineReviewPopover: View {
    @ObservedObject var document: FountainDocument
    let operationID: UUID
    var close: () -> Void
    @State private var error: String?
    @State private var contentHeight: CGFloat = 120
    private var records: [AutomationChange] {
        document.aiReview.changes.filter { $0.operationID == operationID && !$0.reverted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(automationText("AI changes")).font(.headline)
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel(automationText("Close AI review"))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(records) { change in
                        AIReviewChangeSnippet(change: change)
                    }
                }.font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }.frame(height: min(260, contentHeight))
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button(automationText("Reject")) { review(accept: false) }
                Spacer()
                Button(automationText("Accept")) { review(accept: true) }.buttonStyle(.borderedProminent)
            }.disabled(records.isEmpty || records.contains { $0.conflicted || $0.reverted })
        }.padding(16).frame(width: 348)
    }

    private func review(accept: Bool) {
        do {
            if accept { try document.acceptAIChange(operationID: operationID) }
            else { try document.revertAIChanges(id: operationID.uuidString) }
            close()
        } catch { self.error = error.localizedDescription }
    }
}

private struct AIReviewChangeSnippet: View {
    let change: AutomationChange
    var body: some View {
        if !change.before.isEmpty {
            Text(change.before).foregroundStyle(.secondary)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel(L10n.format("Previous text: %@", change.before, table: "Automation"))
        }
        if !change.after.isEmpty {
            Text(change.after).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel(L10n.format("Current text: %@", change.after, table: "Automation"))
        }
    }
}

struct AIReviewPopup: View {
    @ObservedObject var document: FountainDocument
    var close: () -> Void
    @State private var error: String?
    private var batches: [String] {
        Array(NSOrderedSet(array: document.aiReview.changes.map(\.batchID))).compactMap { $0 as? String }.reversed()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Text(automationText("Accept keeps these edits. Reject restores the previous text when it is safe."))
                .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18).padding(.bottom, 12)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if let message = error ?? document.aiReviewError {
                        Text(message).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    }
                    ForEach(batches, id: \.self) { batch in
                        AIReviewBatchSection(document: document, batch: batch, close: close) { self.error = $0 }
                    }
                }.padding(18)
            }
        }.frame(minWidth: 500, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(automationText("AI changes")).font(.headline)
                Text(document.displayName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.plain)
                .accessibilityLabel(automationText("Close AI review"))
        }.padding(18)
    }
}

private struct AIReviewBatchSection: View {
    @ObservedObject var document: FountainDocument
    let batch: String
    var close: () -> Void
    var reportError: (String) -> Void

    private var records: [AutomationChange] { document.aiReview.changes.filter { $0.batchID == batch } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(records.first?.createdAt ?? Date(), style: .time).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(automationText("Dismiss highlights"), action: dismissHighlights).font(.caption).buttonStyle(.link)
            }
            ForEach(records) { change in
                AIReviewChangeCard(document: document, change: change, reportError: reportError)
            }
            batchActions
        }
    }

    private var batchActions: some View {
        HStack {
            Button(batchRejectTitle, action: revertBatch)
                .disabled(records.contains { $0.conflicted || $0.reverted })
            Spacer()
            if records.allSatisfy({ $0.accepted == true }) {
                Text(automationText("Accepted")).foregroundStyle(.secondary)
            } else {
                Button(automationText("Accept"), action: acceptBatch)
                    .buttonStyle(.borderedProminent).disabled(records.contains { $0.conflicted || $0.reverted })
            }
        }
    }

    private var batchRejectTitle: String {
        records.allSatisfy { $0.accepted == true } ? automationText("Revert batch") : automationText("Reject")
    }

    private func dismissHighlights() {
        for index in document.aiReview.changes.indices where document.aiReview.changes[index].batchID == batch {
            document.aiReview.changes[index].dismissed = true
        }
        document.persistAIReview()
    }

    private func revertBatch() {
        do { try document.revertAIChanges(id: batch); reportError("") ; close() }
        catch { reportError(error.localizedDescription) }
    }

    private func acceptBatch() {
        do { try document.acceptAIChanges(batchID: batch); reportError(""); close() }
        catch { reportError(error.localizedDescription) }
    }
}

private struct AIReviewChangeCard: View {
    @ObservedObject var document: FountainDocument
    let change: AutomationChange
    var reportError: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(automationChangeHeadline(change), systemImage: automationChangeSymbol(change))
                    .font(.caption.weight(.semibold)).foregroundStyle(changeTint)
                Spacer()
                if change.reverted {
                    Text(automationText(change.accepted == false ? "Rejected" : "Reverted")).font(.caption).foregroundStyle(.secondary)
                }
            }
            if !change.before.isEmpty { changeBlock(change.before, background: .orange.opacity(0.07), previous: true) }
            if !change.after.isEmpty { changeBlock(change.after, background: .green.opacity(0.07), previous: false) }
            if change.conflicted {
                Text(automationText("Writing changed here. Inspect before reverting.")).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(showTitle, action: showInScreenplay).disabled(change.conflicted || change.reverted)
                Spacer()
                Button(automationText("Revert"), action: revertChange).disabled(change.conflicted || change.reverted)
            }.font(.caption).buttonStyle(.link)
            if change.kind == "move" {
                Text(L10n.format("Move %@", String(change.operationID.uuidString.prefix(6)), table: "Automation"))
                    .font(.caption2.monospaced()).foregroundStyle(.tertiary)
            }
        }
        .textSelection(.enabled).padding(12).background(.background, in: RoundedRectangle(cornerRadius: 8))
    }

    private var changeTint: Color {
        if change.kind == "move" { return .blue }
        return change.after.isEmpty ? .orange : .green
    }

    private var showTitle: String {
        if change.kind == "move" {
            return automationText(change.role == "origin" ? "Show origin" : "Show destination")
        }
        return automationText("Show in screenplay")
    }

    private func changeBlock(_ text: String, background: Color, previous: Bool) -> some View {
        Text(text).font(.system(.callout, design: .monospaced))
            .foregroundStyle(previous ? .secondary : Color.primary)
            .padding(9).frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 5))
            .accessibilityLabel(L10n.format(previous ? "Previous text: %@" : "Current text: %@", text, table: "Automation"))
    }

    private func showInScreenplay() {
        document.automationSelection = change.range
        document.automationSelectionRequest = UUID()
    }

    private func revertChange() {
        do { try document.revertAIChanges(id: change.id.uuidString); reportError("") }
        catch { reportError(error.localizedDescription) }
    }
}