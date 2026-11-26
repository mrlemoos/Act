import ActCore
import AppKit
import SwiftUI

@MainActor
private enum StoryboardImageLoader {
    struct State {
        var image: NSImage?
        var versions: [AutomationImageVersion]
        var selectedID: String
    }

    static func load(shotID: UUID, storyboardRoot: URL, managed: (URL) throws -> URL) throws -> State {
        let manifest = try managed(storyboardRoot.appendingPathComponent("versions.json"))
        guard FileManager.default.fileExists(atPath: manifest.path) else { return State(image: nil, versions: [], selectedID: "") }
        let library = try JSONDecoder().decode(AutomationStoryboardLibrary.self, from: Data(contentsOf: manifest))
        guard library.version == 1 else { throw AutomationFailure("unsupported_version", "Unsupported storyboard library version.") }
        let versions = library.versions.filter { $0.targetID == shotID.uuidString }
        guard let active = versions.first(where: \.active) else { return State(image: nil, versions: versions, selectedID: "") }
        guard CharacterLibraryStore.safeImagePath(active.path) else { throw CharacterSheetError.missingImage }
        let path = try managed(storyboardRoot.appendingPathComponent(active.path))
        guard (try path.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 25_165_824 else {
            throw CharacterSheetError.missingImage
        }
        let validated = try CharacterImageGenerator.validate(Data(contentsOf: path))
        return State(image: NSImage(data: validated.data), versions: versions, selectedID: active.id)
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
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel(automationText("Active storyboard image"))
                Picker(automationText("Image version"), selection: $selectedID) {
                    ForEach(versionRows, id: \.id) { row in
                        Text(row.title).tag(row.id)
                    }
                }
                .frame(maxWidth: 250)
                .onChange(of: selectedID, perform: selectVersion)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .onAppear { refresh() }
        .onChange(of: service.imageRevision) { _ in refresh() }
    }

    private var versionRows: [(id: String, title: String)] {
        versions.enumerated().map { index, version in
            (version.id, L10n.format("Version %lld", index + 1, table: "Automation"))
        }
    }

    private func selectVersion(_ id: String) {
        do {
            let response = try service.perform(.init(operation: "images.select", documentID: document.automationID,
                                                     expectedRevision: document.automationRevision,
                                                     parameters: ["versionID": .string(id)]))
            if response["ok"].bool != true { error = response["error"]["message"].string }
            else { error = nil; refresh() }
        } catch { self.error = error.localizedDescription }
    }

    private func refresh() {
        do {
            guard let root = document.fileURL?.deletingPathExtension().appendingPathExtension("storyboards") else { return }
            let loaded = try StoryboardImageLoader.load(shotID: shotID, storyboardRoot: root, managed: service.managed)
            image = loaded.image
            versions = loaded.versions
            selectedID = loaded.selectedID
            error = nil
        } catch {
            self.error = error.localizedDescription
            image = nil
        }
    }
}