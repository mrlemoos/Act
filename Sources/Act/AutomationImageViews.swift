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
        }.padding(24).frame(minWidth: 500, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
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
                Picker(automationText("Image version"), selection: versionBinding) {
                    ForEach(Array(versions.enumerated()), id: \.element.id) { index, version in
                        Text(L10n.format("Version %lld", index + 1, table: "Automation")).tag(version.id)
                    }
                }.frame(maxWidth: 250)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .onAppear(perform: refresh)
        .onChange(of: service.imageRevision) { _, _ in refresh() }
    }

    private var versionBinding: Binding<String> {
        Binding(get: { selectedID }, set: select)
    }

    private func select(_ id: String) {
        do {
            let response = try service.perform(.init(operation: "images.select", documentID: document.automationID,
                expectedRevision: document.automationRevision, parameters: ["versionID": .string(id)]))
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