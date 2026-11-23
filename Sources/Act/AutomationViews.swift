import ActCore
import AppKit
import SwiftUI

func automationText(_ key: String) -> String { L10n.string(key, table: "Automation") }

@MainActor
final class AutomationPopupController: NSWindowController {
    init<Content: View>(title: String, size: NSSize, content: Content) {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = title; panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 500, height: 420)
        let host = NSHostingView(rootView: content)
        host.sizingOptions = []; panel.contentView = host
        super.init(window: panel)
    }
    required init?(coder: NSCoder) { nil }
    func present() { window?.center(); window?.makeKeyAndOrderFront(nil) }
}

struct AutomationWindow: View {
    @ObservedObject var service: AutomationService
    @State private var command = "{\"version\":1,\"requestID\":\"inspect-1\",\"operation\":\"documents.list\",\"parameters\":{}}"
    @State private var result = automationText("Submit a command to inspect its structured result. Give every new command a unique requestID.")
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text(automationText("Automation")).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(automationText("List documents")) { run(.init(operation: "documents.list")) }.fixedSize()
                    Button(automationText("Review archives")) { run(.init(operation: "reviews.archives")) }.fixedSize()
                    Button(automationText("Command reference")) { run(.init(operation: "schema")) }.fixedSize()
                    Spacer()
                }
                Text(automationText("Commands operate on live documents. Preview edits before applying them.")).foregroundStyle(.secondary)
                Text(automationText("Request")).font(.headline)
                TextEditor(text: $command).font(.system(.body, design: .monospaced))
                    .accessibilityLabel(automationText("Automation request JSON")).frame(minHeight: 70)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(.quaternary))
                HStack {
                    Button(automationText("Submit command")) {
                        let output = service.handle(Data(command.utf8))
                        if let value = try? JSONDecoder().decode(AutomationValue.self, from: output), let pretty = try? value.data(pretty: true) { result = String(decoding: pretty, as: UTF8.self) }
                    }.keyboardShortcut(.return, modifiers: [.command])
                    Spacer()
                    Text(service.root.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(service.root.path).textSelection(.enabled)
                }
                Text(automationText("Result")).font(.headline)
                ScrollView { Text(result).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .accessibilityLabel(automationText("Automation result JSON")).frame(minHeight: 90)
            }.padding(20).frame(maxWidth: .infinity, minHeight: 440, alignment: .topLeading)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error = service.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                    Text(automationText("Generation requests")).font(.headline)
                    if service.jobs.isEmpty { Text(automationText("Image requests and local generation jobs appear here.")).foregroundStyle(.secondary) }
                    ForEach(service.jobs.reversed()) { job in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(automationText(job.targetKind == "shot" ? "Storyboard image" : job.targetKind == "character" ? "Character image" : "Local generation")).font(.headline)
                                Spacer(); Text(automationText(job.state)).font(.caption.monospaced())
                            }
                            Text(URL(fileURLWithPath: job.documentPath).lastPathComponent).foregroundStyle(.secondary)
                            if job.state == "approval_required" {
                                Button(automationText("Review request")) { service.showApprovalPopup(jobID: job.id) }
                            }
                            if let path = job.resultPath, let image = NSImage(contentsOfFile: path) {
                                Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 200).accessibilityLabel(L10n.format("Generated result for %@", job.targetID, table: "Automation"))
                            }
                            if ["shot", "character"].contains(job.targetKind), job.state != "approval_required" {
                                DisclosureGroup(automationText("Request description")) { Text(job.prompt).font(.callout.monospaced()).textSelection(.enabled) }
                            }
                            HStack {
                                if job.state == "stale", job.resultPath != nil {
                                    Button(automationText("Attach reviewed result")) { service.attachReviewedResult(job.id) }
                                }
                                if ["prepared", "approval_required", "running", "ready", "stale"].contains(job.state) {
                                    Button(automationText("Cancel request")) { service.cancelJob(job.id) }
                                }
                            }
                            if let error = job.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                            Text(job.id).font(.caption2.monospaced()).foregroundStyle(.tertiary).textSelection(.enabled)
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.background, in: RoundedRectangle(cornerRadius: 10))
                    }
                }.padding(20)
            }.frame(maxWidth: .infinity, minHeight: 130)
        }.frame(minWidth: 650, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
    }
    private func run(_ request: AutomationRequest) {
        do { result = String(decoding: try service.perform(request).data(pretty: true), as: UTF8.self) }
        catch { result = error.localizedDescription }
    }
}

struct AIInlineReviewPopover: View {
    @ObservedObject var document: FountainDocument
    let operationID: UUID
    var close: () -> Void
    @State private var error: String?
    @State private var contentHeight: CGFloat = 120
    private var records: [AutomationChange] { document.aiReview.changes.filter { $0.operationID == operationID && !$0.reverted } }

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

struct AIReviewPopup: View {
    @ObservedObject var document: FountainDocument
    var close: () -> Void
    @State private var error: String?
    private var batches: [String] { Array(NSOrderedSet(array: document.aiReview.changes.map(\.batchID))).compactMap { $0 as? String }.reversed() }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(automationText("AI changes")).font(.headline)
                    Text(document.displayName).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel(automationText("Close AI review"))
            }.padding(18)
            Text(automationText("Accept keeps these edits. Reject restores the previous text when it is safe.")).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.bottom, 12)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if let message = error ?? document.aiReviewError { Text(message).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
                    ForEach(batches, id: \.self) { batch in
                        VStack(alignment: .leading, spacing: 10) {
                            let records = document.aiReview.changes.filter { $0.batchID == batch }
                            HStack {
                                Text(records.first?.createdAt ?? Date(), style: .time).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button(automationText("Dismiss highlights")) {
                                    for i in document.aiReview.changes.indices where document.aiReview.changes[i].batchID == batch { document.aiReview.changes[i].dismissed = true }
                                    document.persistAIReview()
                                }.font(.caption).buttonStyle(.link)
                            }
                            ForEach(records) { change in card(change) }
                            HStack {
                            Button(automationText(records.allSatisfy { $0.accepted == true } ? "Revert batch" : "Reject")) { revert(batch) }.disabled(records.contains { $0.conflicted || $0.reverted })
                                Spacer()
                                if records.allSatisfy({ $0.accepted == true }) { Text(automationText("Accepted")).foregroundStyle(.secondary) }
                                else {
                                    Button(automationText("Accept")) { accept(batch) }
                                        .buttonStyle(.borderedProminent).disabled(records.contains { $0.conflicted || $0.reverted })
                                }
                            }
                        }
                    }
                }.padding(18)
            }
        }.frame(minWidth: 500, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity).background(Color(nsColor: .windowBackgroundColor))
    }
    private func card(_ change: AutomationChange) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(automationText(change.kind == "move" ? (change.role == "origin" ? "Moved from here" : "Moved here") : change.kind), systemImage: change.kind == "move" ? "arrow.up.arrow.down" : change.after.isEmpty ? "minus.circle" : "plus.circle")
                    .font(.caption.weight(.semibold)).foregroundStyle(change.kind == "move" ? .blue : change.after.isEmpty ? .orange : .green)
                Spacer()
                if change.reverted { Text(automationText(change.accepted == false ? "Rejected" : "Reverted")).font(.caption).foregroundStyle(.secondary) }
            }
            if !change.before.isEmpty {
                Text(change.before).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
                    .padding(9).frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
                    .accessibilityLabel(L10n.format("Previous text: %@", change.before, table: "Automation"))
            }
            if !change.after.isEmpty {
                Text(change.after).font(.system(.callout, design: .monospaced))
                    .padding(9).frame(maxWidth: .infinity, alignment: .leading).background(.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
                    .accessibilityLabel(L10n.format("Current text: %@", change.after, table: "Automation"))
            }
            if change.conflicted { Text(automationText("Writing changed here. Inspect before reverting.")).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button(automationText(change.kind == "move" ? (change.role == "origin" ? "Show origin" : "Show destination") : "Show in screenplay")) {
                    document.automationSelection = change.range; document.automationSelectionRequest = UUID()
                }.disabled(change.conflicted || change.reverted)
                Spacer()
                Button(automationText("Revert")) { revert(change.id.uuidString) }.disabled(change.conflicted || change.reverted)
            }.font(.caption).buttonStyle(.link)
            if change.kind == "move" { Text(L10n.format("Move %@", String(change.operationID.uuidString.prefix(6)), table: "Automation")).font(.caption2.monospaced()).foregroundStyle(.tertiary) }
        }.textSelection(.enabled).padding(12).background(.background, in: RoundedRectangle(cornerRadius: 8))
    }
    private func revert(_ id: String) {
        do {
            let isBatch = document.aiReview.changes.contains { $0.batchID == id }
            try document.revertAIChanges(id: id); error = nil
            if isBatch { close() }
        } catch { self.error = error.localizedDescription }
    }
    private func accept(_ id: String) {
        do { try document.acceptAIChanges(batchID: id); error = nil; close() } catch { self.error = error.localizedDescription }
    }
}

struct ImageApprovalPopup: View {
    @ObservedObject var service: AutomationService
    let job: AutomationJob
    var accept: () -> Void
    var reject: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(automationText("Review request")).font(.title2.bold())
            Text(L10n.format("Review the complete outgoing description and references. This uses your configured %@ account and may incur charges.", job.agent ?? "agent", table: "Automation")).foregroundStyle(.secondary)
            if let error = service.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(job.prompt).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(job.references, id: \.self) { path in
                        if let image = NSImage(contentsOfFile: path) {
                            Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                                .accessibilityLabel(L10n.format("Outgoing reference %@", URL(fileURLWithPath: path).lastPathComponent, table: "Automation"))
                        }
                    }
                }
            }
            Divider()
            HStack {
                Button(automationText("Reject"), action: reject).keyboardShortcut(.cancelAction)
                Spacer()
                Button(automationText("Accept"), action: accept).buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(minWidth: 500, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity).background(Color(nsColor: .windowBackgroundColor))
    }
}

struct StoryboardImageStrip: View {
    @ObservedObject var document: FountainDocument
    @ObservedObject private var service = AutomationService.shared
    let shotID: UUID
    @State private var image: NSImage?
    @State private var versions: [AutomationImageVersion] = []
    @State private var selectedID = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 520, maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityLabel(automationText("Active storyboard image"))
                Picker(automationText("Image version"), selection: Binding(get: { selectedID }, set: select)) {
                    ForEach(Array(versions.enumerated()), id: \.element.id) { index, version in
                        Text(L10n.format("Version %lld", index + 1, table: "Automation")).tag(version.id)
                    }
                }.frame(maxWidth: 250)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }.onAppear(perform: refresh).onChange(of: service.imageRevision) { refresh() }
    }
    private func select(_ id: String) {
        do {
            let response = try service.perform(.init(operation: "images.select", documentID: document.automationID, expectedRevision: document.automationRevision, parameters: ["versionID": .string(id)]))
            if response["ok"].bool != true { error = response["error"]["message"].string }
            else { error = nil; refresh() }
        } catch { self.error = error.localizedDescription }
    }
    private func refresh() {
        do {
            guard let url = document.fileURL?.deletingPathExtension().appendingPathExtension("storyboards") else { return }
            let manifest = try service.managed(url.appendingPathComponent("versions.json"))
            guard FileManager.default.fileExists(atPath: manifest.path) else { image = nil; versions = []; return }
            let library = try JSONDecoder().decode(AutomationStoryboardLibrary.self, from: Data(contentsOf: manifest))
            guard library.version == 1 else { throw AutomationFailure("unsupported_version", "Unsupported storyboard library version.") }
            versions = library.versions.filter { $0.targetID == shotID.uuidString }
            if let active = versions.first(where: \.active) {
                guard CharacterLibraryStore.safeImagePath(active.path) else { throw CharacterSheetError.missingImage }
                let path = try service.managed(url.appendingPathComponent(active.path))
                guard (try path.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 25_165_824 else { throw CharacterSheetError.missingImage }
                let validated = try CharacterImageGenerator.validate(Data(contentsOf: path))
                image = NSImage(data: validated.data); selectedID = active.id
            } else { image = nil; selectedID = "" }
        } catch { self.error = error.localizedDescription; image = nil }
    }
}
