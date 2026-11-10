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
                    throw CharacterSheetError.operation("A character folder already exists at the new screenplay location. The original library is preserved; reopen to load the destination library.")
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
            status = "Character marked. Extract physical details when ready."
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
            alert.messageText = "Replace this prompt with extracted details?"
            alert.informativeText = "Your current prompt will be replaced. Existing image versions retain the prompts used to create them."
            alert.addButton(withTitle: "Replace Prompt"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        updatePrompt(character.suggestedPrompt, id: id)
    }

    func extract(id: UUID) {
        guard !isBusy, let character = library.characters.first(where: { $0.id == id }) else { return }
        guard let mlxExecutable, let mlxModel else { error = "Choose an MLX runtime and downloaded model in Character Tools first."; return }
        guard !character.marks.isEmpty, !character.marks.contains(where: \.isDetached) else { error = CharacterSheetError.staleMark.localizedDescription; return }
        let snapshots = character.marks
        isBusy = true; status = "Extracting physical details locally with MLX…"
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
                      library.characters[index].marks == snapshots else { throw CharacterSheetError.operation("Action paragraphs changed during extraction. Retry with the updated text.") }
                var updated = library
                for m in updated.characters[index].marks.indices {
                    updated.characters[index].marks[m].traits = details[updated.characters[index].marks[m].id] ?? []
                    updated.characters[index].marks[m].extractedParagraph = updated.characters[index].marks[m].paragraph
                }
                if updated.characters[index].prompt.isEmpty { updated.characters[index].prompt = updated.characters[index].suggestedPrompt }
                library = updated; save()
                status = "Physical details ready for review. Your existing prompt is preserved."
            } catch is CancellationError { status = "Extraction cancelled. Existing details preserved." }
            catch { self.error = error.localizedDescription; status = "Extraction failed. Existing details preserved." }
        }
    }

    func generate(id: UUID, iterate: Bool) {
        guard !isBusy, !loadFailed, let character = library.characters.first(where: { $0.id == id }), let connection = selectedConnection else { return }
        guard let directory else { error = "Save the screenplay before generating a character sheet."; return }
        save()
        guard !isDirty else { return }
        guard !iterate || connection.canEdit else { error = "Verify reference-image editing for this agent first."; return }
        do {
            let reference = iterate ? try imageData(for: character.activeVersion) : nil
            guard !iterate || reference != nil else { throw CharacterSheetError.missingImage }
            guard approve(prompt: character.prompt, agent: connection.agent, reference: reference) else { return }
            let prompt = character.prompt, referenceID = iterate ? character.activeVersionID : nil
            isBusy = true; status = iterate ? "Iterating on the active sheet…" : "Generating character sheet…"
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
                    status = "New sheet imported. Previous versions preserved."
                } catch is CancellationError { status = "Generation cancelled. Previous sheets preserved." }
                catch { self.error = error.localizedDescription; status = "Generation failed. Prompt and previous sheets preserved." }
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
        panel.title = model ? "Choose downloaded MLX model directory" : "Choose mlx_lm.generate executable"
        panel.canChooseDirectories = model; panel.canChooseFiles = !model
        panel.showsHiddenFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if model { mlxModel = url; defaults.set(url.path, forKey: "Act.characterMLXModel") }
        else if FileManager.default.isExecutableFile(atPath: url.path) { mlxExecutable = url; defaults.set(url.path, forKey: "Act.characterMLXExecutable") }
        else { error = "Choose an executable mlx_lm.generate file." }
    }

    func connection(for agent: CharacterImageAgent) -> ImageAgentConnection? { connections.first { $0.agent == agent } }

    func chooseAgent(_ agent: CharacterImageAgent) {
        let panel = NSOpenPanel(); panel.title = "Choose \(agent.title) executable"; panel.showsHiddenFiles = true
        guard panel.runModal() == .OK, let url = panel.url, FileManager.default.isExecutableFile(atPath: url.path) else { return }
        connections.removeAll { $0.agent == agent }
        connections.append(.init(agent: agent, executable: url)); persistConnections()
    }

    func verify(_ agent: CharacterImageAgent, editing: Bool) {
        guard !isBusy else { return }
        guard var connection = connection(for: agent) ?? agent.discoveredExecutable.map({ ImageAgentConnection(agent: agent, executable: $0) }) else {
            error = "Install and sign in to \(agent.title), or choose its executable."; return
        }
        let reference = editing ? connection.verificationImage : nil
        guard !editing || (connection.canGenerate && reference != nil) else { error = "Verify image generation first."; return }
        let prompt = editing ? CharacterImageAgent.editingVerificationPrompt : CharacterImageAgent.verificationPrompt
        guard approve(prompt: prompt, agent: agent, reference: reference) else { return }
        isBusy = true; status = "Testing \(agent.title) \(editing ? "reference editing" : "image generation")…"
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
                status = "\(agent.title) returned a valid image. Inspect the test result to check \(editing ? "the requested edit" : "the grey cube")."
                // Capability tests return a real image, so users can inspect semantic success as well as file validity.
                showVerification(image.data, agent: agent, editing: editing)
            } catch is CancellationError { status = "Agent test cancelled." }
            catch {
                if let index = connections.firstIndex(where: { $0.agent == agent }) {
                    if editing { connections[index].editingVerified = false } else { connections[index].generationVerified = false; connections[index].editingVerified = false }
                    persistConnections()
                }
                self.error = error.localizedDescription; status = "Agent test failed. No capability enabled."
            }
        }
    }

    private func showVerification(_ data: Data, agent: CharacterImageAgent, editing: Bool) {
        let alert = NSAlert(); alert.messageText = "Did \(agent.title) \(editing ? "change the cube to blue" : "generate a grey cube")?"
        alert.informativeText = "Confirm only if the image matches the test. A valid image file alone does not prove the requested tool worked."
        let view = NSImageView(frame: NSRect(x: 0, y: 0, width: 360, height: 250)); view.imageScaling = .scaleProportionallyUpOrDown; view.image = NSImage(data: data)
        alert.accessoryView = view; alert.addButton(withTitle: "Confirm"); alert.addButton(withTitle: "Failed")
        if alert.runModal() != .alertFirstButtonReturn, let index = connections.firstIndex(where: { $0.agent == agent }) {
            if editing { connections[index].editingVerified = false } else { connections[index].generationVerified = false; connections[index].editingVerified = false }
            persistConnections()
        }
    }

    private func persistConnections() { defaults.set(try? JSONEncoder().encode(connections), forKey: "Act.imageAgentConnections") }
    func cancel() { task?.cancel() }

    private func approve(prompt: String, agent: CharacterImageAgent, reference: Data?) -> Bool {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "Write or extract a prompt first."; return false }
        let alert = NSAlert(); alert.messageText = "Send this prompt to \(agent.title)?"
        alert.informativeText = "This request uses the agent's configured account and image tools and may incur charges. Act supplies this description\(reference == nil ? "" : " and the displayed reference image"), plus instructions for saving the result. No screenplay file is attached. Your configured agent may add its own instructions."
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 220)); scroll.hasVerticalScroller = true
        let text = NSTextView(frame: scroll.bounds); text.isEditable = false; text.isRichText = false; text.string = prompt; text.font = .systemFont(ofSize: 12)
        scroll.documentView = text; stack.addArrangedSubview(scroll)
        if let reference {
            let image = NSImageView(frame: NSRect(x: 0, y: 0, width: 480, height: 180)); image.imageScaling = .scaleProportionallyUpOrDown; image.image = NSImage(data: reference)
            stack.addArrangedSubview(image)
        }
        alert.accessoryView = stack; alert.addButton(withTitle: "Send and Generate"); alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
