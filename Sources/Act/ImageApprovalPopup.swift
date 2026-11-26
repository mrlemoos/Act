import ActCore
import AppKit
import SwiftUI

struct ImageApprovalPopup: View {
    @ObservedObject var service: AutomationService
    let job: AutomationJob
    var accept: () -> Void
    var reject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(automationText("Review request")).font(.title2.bold())
            Text(L10n.format("Review the complete outgoing description and references. This uses your configured %@ account and may incur charges.", job.agent ?? "agent", table: "Automation"))
                .foregroundStyle(.secondary)
            if let error = service.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(job.prompt).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(job.references, id: \.self, content: referenceImage)
                }
            }
            Divider()
            HStack {
                Button(automationText("Reject"), action: reject).keyboardShortcut(.cancelAction)
                Spacer()
                Button(automationText("Accept"), action: accept).buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 500, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func referenceImage(_ path: String) -> some View {
        Group {
            if let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                    .accessibilityLabel(L10n.format("Outgoing reference %@", URL(fileURLWithPath: path).lastPathComponent, table: "Automation"))
            }
        }
    }
}