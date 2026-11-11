import ActCore
import AppKit
import SwiftUI

@MainActor
final class CharacterWorkspaceModel: ObservableObject {
    @Published var library = CharacterLibrary() {
        didSet {
            guard !restoring else { return }
            isDirty = true
            revision += 1
            pendingSave?.cancel()
            pendingSave = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                self?.save()
            }
        }
    }
    @Published var selectedID: UUID?
    @Published var revision = 0
    @Published var error: String?
    @Published var status = ""
    @Published private(set) var isDirty = false
    @Published private(set) var isBusy = false
    @Published var selectedAgent: CharacterImageAgent?
    @Published var connections: [ImageAgentConnection] = []
    @Published var mlxExecutable: URL?
    @Published var mlxModel: URL?
    @Published private(set) var directory: URL?
    private var baseline: Data?
    private var source = ""
    private var restoring = false
    private var loadFailed = false
    private var task: Task<Void, Never>?
    private var pendingSave: Task<Void, Never>?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mlxExecutable = defaults.string(forKey: "Act.characterMLXExecutable").map { URL(fileURLWithPath: $0) } ?? MLXExtractionConfiguration.discoveredExecutable
        mlxModel = defaults.string(forKey: "Act.characterMLXModel").map { URL(fileURLWithPath: $0) }
        if let data = defaults.data(forKey: "Act.imageAgentConnections"), let decoded = try? JSONDecoder().decode([ImageAgentConnection].self, from: data) {
            connections = decoded
            selectedAgent = availableAgents.first?.agent
        }
    }

    var availableAgents: [ImageAgentConnection] { connections.filter(\.canGenerate) }
    var selectedCharacter: CharacterReference? { library.characters.first { $0.id == selectedID } }
    var selectedConnection: ImageAgentConnection? { availableAgents.first { $0.agent == selectedAgent } }

    func prepare(screenplayURL: URL?, source: String) {
        guard let screenplayURL else { self.source = source; return }
        let newDirectory = CharacterLibraryStore.directory(for: screenplayURL)
        guard newDirectory != directory else { return }
        cancel()
        pendingSave?.cancel()
        let manifest = newDirectory.appendingPathComponent("characters.json")
        do {
            if let oldDirectory = directory, !library.characters.isEmpty {
                // Save As copies assets. The original portable folder remains intact.
                save()
                guard !isDirty else { return }
                guard !FileManager.default.fileExists(atPath: newDirectory.path) else {
                    throw CharacterSheetError.operation(L10n.string("A character folder already exists at the new screenplay location. The original library is preserved; reopen to load the destination library.", table: "Characters"))
                }
                if FileManager.default.fileExists(atPath: oldDirectory.path) { try FileManager.default.copyItem(at: oldDirectory, to: newDirectory) }
            }
            directory = newDirectory
            self.source = source
            restoring = true
            defer { restoring = false }
            if FileManager.default.fileExists(atPath: manifest.path) {
                let data = try Data(contentsOf: manifest)
                var loaded = try CharacterLibraryStore.decode(data)
                loaded.verify(source: source)
                library = loaded; baseline = data
                isDirty = try CharacterLibraryStore.data(loaded) != data
            } else { baseline = nil; isDirty = !library.characters.isEmpty }
            loadFailed = false
            if selectedID == nil { selectedID = library.characters.first?.id }
            revision += 1
        } catch { loadFailed = true; self.error = error.localizedDescription }
    }

    func updateSource(_ newSource: String) {
        guard newSource != source else { return }
        if !library.characters.isEmpty { library.reconcile(from: source, to: newSource) }
        source = newSource
    }

    @discardableResult
    func mark(selection: NSRange, characterID: UUID? = nil) -> Bool {
        guard !isBusy, !loadFailed else { return false }
        do {
            var updated = library
            let id = try updated.mark(source: source, selection: selection, characterID: characterID)
            library = updated; selectedID = id
            save()
            status = L10n.string("Character marked. Extract physical details when ready.", table: "Characters")
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func save() {
        pendingSave?.cancel(); pendingSave = nil
        guard isDirty, let directory, !loadFailed else { return }
        do {
            let file = directory.appendingPathComponent("characters.json")
            let onDisk = FileManager.default.fileExists(atPath: file.path) ? try Data(contentsOf: file) : nil
            guard onDisk == baseline else { throw CharacterSheetError.externalChange }
            let data = try CharacterLibraryStore.data(library)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            baseline = data; isDirty = false
        } catch { self.error = error.localizedDescription }
    }

    func updatePrompt(_ value: String, id: UUID) {
        guard let index = library.characters.firstIndex(where: { $0.id == id }) else { return }
        library.characters[index].prompt = value
    }

    func useExtractedDetails(id: UUID) {
        guard let character = library.characters.first(where: { $0.id == id }) else { return }
        if !character.prompt.isEmpty {
            let alert = NSAlert()
            alert.messageText = L10n.string("Replace this prompt with extracted details?", table: "Characters")
            alert.informativeText = L10n.string("Your current prompt will be replaced. Existing image versions retain the prompts used to create them.", table: "Characters")
            alert.addButton(withTitle: L10n.string("Replace Prompt", table: "Characters")); alert.addButton(withTitle: L10n.string("Cancel", table: "Characters"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        updatePrompt(character.suggestedPrompt, id: id)
    }

    func extract(id: UUID) {
        guard !isBusy, let character = library.characters.first(where: { $0.id == id }) else { return }
        guard let mlxExecutable, let mlxModel else { error = L10n.string("Choose an MLX runtime and downloaded model in Character Tools first.", table: "Characters"); return }
        guard !character.marks.isEmpty, !character.marks.contains(where: \.isDetached) else { error = CharacterSheetError.staleMark.localizedDescription; return }
        let snapshots = character.marks
        isBusy = true; status = L10n.string("Extracting physical details locally with MLX…", table: "Characters")
        task = Task {
            defer { isBusy = false; task = nil }
            do {
                var details: [UUID: [PhysicalTrait]] = [:]
                for mark in snapshots {
                    try Task.checkCancellation()
                    details[mark.id] = try await CharacterPhysicalExtractor.extract(name: mark.name, paragraph: mark.paragraph,
                        configuration: .init(executable: mlxExecutable, modelDirectory: mlxModel))
                }
                try Task.checkCancellation()
                guard let index = library.characters.firstIndex(where: { $0.id == id }),
                      library.characters[index].marks == snapshots else { throw CharacterSheetError.operation(L10n.string("Action paragraphs changed during extraction. Retry with the updated text.", table: "Characters")) }
                var updated = library
                for m in updated.characters[index].marks.indices {
                    updated.characters[index].marks[m].traits = details[updated.characters[index].marks[m].id] ?? []
                    updated.characters[index].marks[m].extractedParagraph = updated.characters[index].marks[m].paragraph
                }
                if updated.characters[index].prompt.isEmpty { updated.characters[index].prompt = updated.characters[index].suggestedPrompt }
                library = updated; save()
                status = L10n.string("Physical details ready for review. Your existing prompt is preserved.", table: "Characters")
            } catch is CancellationError { status = L10n.string("Extraction cancelled. Existing details preserved.", table: "Characters") }
            catch { self.error = error.localizedDescription; status = L10n.string("Extraction failed. Existing details preserved.", table: "Characters") }
        }
    }

    func generate(id: UUID, iterate: Bool) {
        guard !isBusy, !loadFailed, let character = library.characters.first(where: { $0.id == id }), let connection = selectedConnection else { return }
        guard let directory else { error = L10n.string("Save the screenplay before generating a character sheet.", table: "Characters"); return }
        save()
        guard !isDirty else { return }
        guard !iterate || connection.canEdit else { error = L10n.string("Verify reference-image editing for this agent first.", table: "Characters"); return }
        do {
            let reference = iterate ? try imageData(for: character.activeVersion) : nil
            guard !iterate || reference != nil else { throw CharacterSheetError.missingImage }
            guard approve(prompt: character.prompt, agent: connection.agent, reference: reference) else { return }
            let prompt = character.prompt, referenceID = iterate ? character.activeVersionID : nil
            isBusy = true; status = iterate ? L10n.string("Iterating on the active sheet…", table: "Characters") : L10n.string("Generating character sheet…", table: "Characters")
            task = Task {
                defer { isBusy = false; task = nil }
                do {
                    let image = try await CharacterImageGenerator.generate(agent: connection.agent, executable: URL(fileURLWithPath: connection.executablePath), prompt: prompt, reference: reference)
                    try Task.checkCancellation()
                    guard self.directory == directory, let index = library.characters.firstIndex(where: { $0.id == id }) else { throw CancellationError() }
                    let path = "images/\(UUID().uuidString).\(image.fileExtension)"
                    try FileManager.default.createDirectory(at: directory.appendingPathComponent("images"), withIntermediateDirectories: true)
                    try image.data.write(to: directory.appendingPathComponent(path), options: .withoutOverwriting)
                    let version = CharacterSheetVersion(imageFile: path, prompt: prompt, agent: connection.agent.rawValue, referenceVersionID: referenceID)
                    library.characters[index].versions.append(version)
                    library.characters[index].activeVersionID = version.id
                    save()
                    status = L10n.string("New sheet imported. Previous versions preserved.", table: "Characters")
                } catch is CancellationError { status = L10n.string("Generation cancelled. Previous sheets preserved.", table: "Characters") }
                catch { self.error = error.localizedDescription; status = L10n.string("Generation failed. Prompt and previous sheets preserved.", table: "Characters") }
            }
        } catch { self.error = error.localizedDescription }
    }

    func imageData(for version: CharacterSheetVersion?) throws -> Data? {
        guard let version, let directory, CharacterLibraryStore.safeImagePath(version.imageFile) else { return nil }
        let url = directory.appendingPathComponent(version.imageFile).resolvingSymlinksInPath()
        guard url.path.hasPrefix(directory.resolvingSymlinksInPath().path + "/images/"),
              (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 25_165_824 else { throw CharacterSheetError.missingImage }
        return try CharacterImageGenerator.validate(Data(contentsOf: url)).data
    }

    func chooseMLX(model: Bool) {
        let panel = NSOpenPanel()
        panel.title = model ? L10n.string("Choose downloaded MLX model directory", table: "Characters") : L10n.string("Choose mlx_lm.generate executable", table: "Characters")
        panel.canChooseDirectories = model; panel.canChooseFiles = !model
        panel.showsHiddenFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if model { mlxModel = url; defaults.set(url.path, forKey: "Act.characterMLXModel") }
        else if FileManager.default.isExecutableFile(atPath: url.path) { mlxExecutable = url; defaults.set(url.path, forKey: "Act.characterMLXExecutable") }
        else { error = L10n.string("Choose an executable mlx_lm.generate file.", table: "Characters") }
    }

    func connection(for agent: CharacterImageAgent) -> ImageAgentConnection? { connections.first { $0.agent == agent } }

    func chooseAgent(_ agent: CharacterImageAgent) {
        let panel = NSOpenPanel(); panel.title = L10n.format("Choose %@ executable", agent.title, table: "Characters"); panel.showsHiddenFiles = true
        guard panel.runModal() == .OK, let url = panel.url, FileManager.default.isExecutableFile(atPath: url.path) else { return }
        connections.removeAll { $0.agent == agent }
        connections.append(.init(agent: agent, executable: url)); persistConnections()
    }

    func verify(_ agent: CharacterImageAgent, editing: Bool) {
        guard !isBusy else { return }
        guard var connection = connection(for: agent) ?? agent.discoveredExecutable.map({ ImageAgentConnection(agent: agent, executable: $0) }) else {
            error = L10n.format("Install and sign in to %@, or choose its executable.", agent.title, table: "Characters"); return
        }
        let reference = editing ? connection.verificationImage : nil
        guard !editing || (connection.canGenerate && reference != nil) else { error = L10n.string("Verify image generation first.", table: "Characters"); return }
        let prompt = editing ? CharacterImageAgent.editingVerificationPrompt : CharacterImageAgent.verificationPrompt
        guard approve(prompt: prompt, agent: agent, reference: reference) else { return }
        isBusy = true; status = L10n.format(editing ? "Testing %@ reference editing…" : "Testing %@ image generation…", agent.title, table: "Characters")
        task = Task {
            defer { isBusy = false; task = nil }
            do {
                let image = try await CharacterImageGenerator.generate(agent: agent, executable: URL(fileURLWithPath: connection.executablePath), prompt: prompt, reference: reference)
                try Task.checkCancellation()
                connection.executableFingerprint = ImageAgentConnection.fingerprint(URL(fileURLWithPath: connection.executablePath))
                connection.generationVerified = true
                if editing { connection.editingVerified = true }
                else { connection.verificationImage = image.data; connection.editingVerified = false }
                connections.removeAll { $0.agent == agent }; connections.append(connection)
                selectedAgent = agent; persistConnections()
                status = L10n.format(editing ? "%@ returned a valid image. Inspect the test result to check the requested edit." : "%@ returned a valid image. Inspect the test result to check the grey cube.", agent.title, table: "Characters")
                // Capability tests return a real image, so users can inspect semantic success as well as file validity.
                showVerification(image.data, agent: agent, editing: editing)
            } catch is CancellationError { status = L10n.string("Agent test cancelled.", table: "Characters") }
            catch {
                if let index = connections.firstIndex(where: { $0.agent == agent }) {
                    if editing { connections[index].editingVerified = false } else { connections[index].generationVerified = false; connections[index].editingVerified = false }
                    persistConnections()
                }
                self.error = error.localizedDescription; status = L10n.string("Agent test failed. No capability enabled.", table: "Characters")
            }
        }
    }

    private func showVerification(_ data: Data, agent: CharacterImageAgent, editing: Bool) {
        let alert = NSAlert(); alert.messageText = L10n.format(editing ? "Did %@ change the cube to blue?" : "Did %@ generate a grey cube?", agent.title, table: "Characters")
        alert.informativeText = L10n.string("Confirm only if the image matches the test. A valid image file alone does not prove the requested tool worked.", table: "Characters")
        let view = NSImageView(frame: NSRect(x: 0, y: 0, width: 360, height: 250)); view.imageScaling = .scaleProportionallyUpOrDown; view.image = NSImage(data: data)
        alert.accessoryView = view; alert.addButton(withTitle: L10n.string("Confirm", table: "Characters")); alert.addButton(withTitle: L10n.string("Failed", table: "Characters"))
        if alert.runModal() != .alertFirstButtonReturn, let index = connections.firstIndex(where: { $0.agent == agent }) {
            if editing { connections[index].editingVerified = false } else { connections[index].generationVerified = false; connections[index].editingVerified = false }
            persistConnections()
        }
    }

    private func persistConnections() { defaults.set(try? JSONEncoder().encode(connections), forKey: "Act.imageAgentConnections") }
    func cancel() { task?.cancel() }

    private func approve(prompt: String, agent: CharacterImageAgent, reference: Data?) -> Bool {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = L10n.string("Write or extract a prompt first.", table: "Characters"); return false }
        let alert = NSAlert(); alert.messageText = L10n.format("Send this prompt to %@?", agent.title, table: "Characters")
        alert.informativeText = L10n.string(reference == nil ? "This request uses the agent's configured account and image tools and may incur charges. Act supplies this description, plus instructions for saving the result. No screenplay file is attached. Your configured agent may add its own instructions." : "This request uses the agent's configured account and image tools and may incur charges. Act supplies this description and the displayed reference image, plus instructions for saving the result. No screenplay file is attached. Your configured agent may add its own instructions.", table: "Characters")
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 220)); scroll.hasVerticalScroller = true
        let text = NSTextView(frame: scroll.bounds); text.isEditable = false; text.isRichText = false; text.string = prompt; text.font = .systemFont(ofSize: 12)
        scroll.documentView = text; stack.addArrangedSubview(scroll)
        if let reference {
            let image = NSImageView(frame: NSRect(x: 0, y: 0, width: 480, height: 180)); image.imageScaling = .scaleProportionallyUpOrDown; image.image = NSImage(data: reference)
            stack.addArrangedSubview(image)
        }
        alert.accessoryView = stack; alert.addButton(withTitle: L10n.string("Send and Generate", table: "Characters")); alert.addButton(withTitle: L10n.string("Cancel", table: "Characters"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}
