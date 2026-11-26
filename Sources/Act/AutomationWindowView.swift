import ActCore
import AppKit
import SwiftUI

struct AutomationWindow: View {
    @ObservedObject var service: AutomationService
    @State private var command = "{\"version\":1,\"requestID\":\"inspect-1\",\"operation\":\"documents.list\",\"parameters\":{}}"
    @State private var result = automationText("Submit a command to inspect its structured result. Give every new command a unique requestID.")

    var body: some View {
        VStack(spacing: 0) {
            requestPanel
            Divider()
            jobList
        }
        .frame(minWidth: 650, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
    }

    private var requestPanel: some View {
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
                Button(automationText("Submit command"), action: submitCommand).keyboardShortcut(.return, modifiers: [.command])
                Spacer()
                Text(service.root.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    .help(service.root.path).textSelection(.enabled)
            }
            Text(automationText("Result")).font(.headline)
            ScrollView {
                Text(result).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityLabel(automationText("Automation result JSON")).frame(minHeight: 90)
        }
        .padding(20).frame(maxWidth: .infinity, minHeight: 440, alignment: .topLeading)
    }

    private var jobList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error = service.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                Text(automationText("Generation requests")).font(.headline)
                if service.jobs.isEmpty {
                    Text(automationText("Image requests and local generation jobs appear here.")).foregroundStyle(.secondary)
                }
                ForEach(service.jobs.reversed()) { job in
                    AutomationJobRow(service: service, job: job)
                }
            }.padding(20)
        }.frame(maxWidth: .infinity, minHeight: 130)
    }

    private func submitCommand() {
        let output = service.handle(Data(command.utf8))
        guard let value = try? JSONDecoder().decode(AutomationValue.self, from: output),
              let pretty = try? value.data(pretty: true) else { return }
        result = String(decoding: pretty, as: UTF8.self)
    }

    private func run(_ request: AutomationRequest) {
        do { result = String(decoding: try service.perform(request).data(pretty: true), as: UTF8.self) }
        catch { result = error.localizedDescription }
    }
}

private struct AutomationJobRow: View {
    @ObservedObject var service: AutomationService
    let job: AutomationJob
    private var showsPrompt: Bool { ["shot", "character"].contains(job.targetKind) && job.state != "approval_required" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(automationJobTitle(job.targetKind)).font(.headline)
                Spacer()
                Text(automationText(job.state)).font(.caption.monospaced())
            }
            Text(URL(fileURLWithPath: job.documentPath).lastPathComponent).foregroundStyle(.secondary)
            if job.state == "approval_required" {
                Button(automationText("Review request")) { service.showApprovalPopup(jobID: job.id) }
            }
            if let path = job.resultPath, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 200)
                    .accessibilityLabel(L10n.format("Generated result for %@", job.targetID, table: "Automation"))
            }
            if showsPrompt {
                DisclosureGroup(automationText("Request description")) {
                    Text(job.prompt).font(.callout.monospaced()).textSelection(.enabled)
                }
            }
            jobActions
            if let error = job.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            Text(job.id).font(.caption2.monospaced()).foregroundStyle(.tertiary).textSelection(.enabled)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
    }

  private var jobActions: some View {
        HStack {
            if job.state == "stale", job.resultPath != nil {
                Button(automationText("Attach reviewed result")) { service.attachReviewedResult(job.id) }
            }
            let cancellable = ["prepared", "approval_required", "running", "ready", "stale"]
            if cancellable.contains(job.state) {
                Button(automationText("Cancel request")) { service.cancelJob(job.id) }
            }
        }
    }
}