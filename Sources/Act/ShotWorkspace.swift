import SwiftUI
import AppKit
import ActCore
import UniformTypeIdentifiers

@MainActor
final class ShotWorkspaceModel: ObservableObject {
    @Published var list = ShotListDocument(source: "") {
        didSet {
            guard !restoring else { return }
            isDirty = true
            persistRecovery()
        }
    }
    @Published var selectedSceneID = ""
    @Published var isDirty = false
    @Published var fileURL: URL?
    @Published var error: String?
    @Published var status = ""
    @Published var isGenerating = false
    @Published var isDownloading = false
    @Published var modelURL: URL?
    @Published var executableURL = LocalGenerationConfiguration.discoveredExecutableURL
    private var baseline: Data?
    private var restoring = false
    private var task: Task<Void, Never>?
    private var recoveryIdentity: String?
    private var screenplayFingerprint = ""
    private var recoveryStore: ShotRecoveryStore {
        ShotRecoveryStore(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Act/ShotRecovery", isDirectory: true))
    }
    private var recoveryRecord: ShotRecoveryRecord {
        ShotRecoveryRecord(document: list, path: fileURL?.path, baseline: baseline, isDirty: isDirty, screenplayFingerprint: screenplayFingerprint, screenplayIdentity: recoveryIdentity ?? "")
    }
    private var modelStore: LocalModelStore {
        LocalModelStore(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Act/Models", isDirectory: true))
    }

    init() {
        let defaults = UserDefaults.standard
        if let path = defaults.string(forKey: "Act.localModelPath"), FileManager.default.fileExists(atPath: path) { modelURL = URL(fileURLWithPath: path) }
        if let path = defaults.string(forKey: "Act.localRuntimePath"), FileManager.default.isExecutableFile(atPath: path) { executableURL = URL(fileURLWithPath: path) }
        if modelURL == nil && modelStore.isDownloaded { modelURL = modelStore.modelURL }
    }

    func prepare(source: String, name: String?, identity: String) {
        guard recoveryIdentity == nil else { return }
        recoveryIdentity = identity
        screenplayFingerprint = SceneAnchor.digest(source)
        restoring = true
        defer { restoring = false }
        if let recovered = recoveryStore.load(identity: identity, source: source) {
            list = recovered.document
            fileURL = recovered.path.map { URL(fileURLWithPath: $0) }
            baseline = recovered.baseline
            isDirty = recovered.isDirty
            status = recovered.isDirty ? L10n.string("Recovered unsaved shot-list edits. Save to keep them.", table: "Shots") : L10n.string("Reopened your shot list.", table: "Shots")
            if recovered.screenplayIdentity != identity {
                do { try recoveryStore.relocate(from: recovered.screenplayIdentity, to: identity, record: recoveryRecord) }
                catch { self.error = L10n.format("Could not move recovered shot-list edits: %@", error.localizedDescription, table: "Shots") }
            }
        } else {
            list = ShotListDocument(title: "\(name ?? "Untitled") shots", screenplayName: name, source: source)
        }
    }

    func updateScreenplaySource(_ source: String) {
        screenplayFingerprint = SceneAnchor.digest(source)
        if recoveryIdentity != nil { persistRecovery() }
    }

    func relocateRecovery(identity: String) {
        guard let oldIdentity = recoveryIdentity, oldIdentity != identity else { return }
        do {
            try recoveryStore.relocate(from: oldIdentity, to: identity, record: recoveryRecord)
            recoveryIdentity = identity
        } catch { self.error = L10n.format("Could not move shot-list recovery after saving your screenplay: %@", error.localizedDescription, table: "Shots") }
    }

    func addShot(anchor: SceneAnchor) {
        guard !isGenerating else { return }
        if !list.anchors.contains(where: { $0.id == anchor.id }) { list.acknowledge(anchor) }
        list.shots.append(Shot(sceneID: anchor.id, framing: "Wide", action: "", cameraMovement: "Static", rationale: ""))
    }

    func removeShot(_ id: UUID) {
        guard !isGenerating else { return }
        list.shots.removeAll { $0.id == id }
    }

    func save(asCopy: Bool = false) {
        do {
            if !asCopy, let fileURL {
                let onDisk = try Data(contentsOf: fileURL)
                guard onDisk == baseline else {
                    error = L10n.string("The shot-list file changed outside Act. Open it again to reload, or use Save Copy to preserve your edits separately.", table: "Shots")
                    return
                }
                try write(to: fileURL)
                return
            }
            let panel = NSSavePanel()
            panel.title = L10n.string("Save shot list", table: "Shots")
            panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "\(list.screenplayName ?? "Untitled").shots.json"
            panel.allowedContentTypes = [.json]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try write(to: url)
        } catch { self.error = error.localizedDescription }
    }

    func open() {
        guard !isGenerating, !isDownloading else { error = L10n.string("Cancel the current operation before opening another shot list.", table: "Shots"); return }
        guard discardConfirmed() else { return }
        let panel = NSOpenPanel()
        panel.title = L10n.string("Open shot list", table: "Shots")
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let loaded = try ShotListStore.decode(data)
            restoring = true
            list = loaded
            restoring = false
            fileURL = url
            baseline = data
            isDirty = false
            status = L10n.format("Opened %@", url.lastPathComponent, table: "Shots")
            persistRecovery()
        } catch { self.error = error.localizedDescription }
    }

    func openLinked(_ url: URL) throws {
        guard !isGenerating, !isDownloading, !isDirty else {
            throw DocumentError.externalChange
        }
        let data = try Data(contentsOf: url)
        let loaded = try ShotListStore.decode(data)
        restoring = true
        list = loaded
        restoring = false
        fileURL = url; baseline = data; isDirty = false
        status = L10n.format("Opened %@", url.lastPathComponent, table: "Shots")
        persistRecovery()
    }

    func chooseModel() {
        let panel = NSOpenPanel()
        panel.title = L10n.string("Choose a GGUF model", table: "Shots")
        panel.message = L10n.string("Choose a local instruct model supported by llama.cpp. No screenplay text leaves your Mac.", table: "Shots")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.pathExtension.lowercased() == "gguf" else { error = L10n.string("Choose a GGUF model file.", table: "Shots"); return }
        modelURL = url
        UserDefaults.standard.set(url.path, forKey: "Act.localModelPath")
    }

    func chooseRuntime() {
        let panel = NSOpenPanel()
        panel.title = L10n.string("Choose llama.cpp runtime", table: "Shots")
        panel.message = L10n.string("Select the llama.cpp llama-completion or llama-cli executable. It runs locally using your Mac's GPU.", table: "Shots")
        panel.showsHiddenFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard FileManager.default.isExecutableFile(atPath: url.path) else { error = L10n.string("Choose an executable llama-cli binary.", table: "Shots"); return }
        executableURL = url
        UserDefaults.standard.set(url.path, forKey: "Act.localRuntimePath")
    }

    func downloadModel() {
        guard !isDownloading else { return }
        isDownloading = true
        status = L10n.string("Downloading and verifying the model. Screenplay text stays on this Mac.", table: "Shots")
        task = Task {
            defer { isDownloading = false; task = nil }
            do {
                let url = try await modelStore.download()
                modelURL = url
                UserDefaults.standard.set(url.path, forKey: "Act.localModelPath")
                status = L10n.string("Model ready. Generation works offline.", table: "Shots")
            } catch is CancellationError { status = L10n.string("Download cancelled.", table: "Shots") }
            catch where Task.isCancelled { status = L10n.string("Download cancelled.", table: "Shots") }
            catch { self.error = error.localizedDescription; status = L10n.string("Model download failed. You can retry.", table: "Shots") }
        }
    }

    func generate(scene: FountainScene, source: String) {
        guard !isGenerating, !isDownloading else { return }
        guard let executableURL, let modelURL else { error = L10n.string("Choose a local runtime and model first.", table: "Shots"); return }
        let anchor = SceneAnchor(id: scene.id, heading: scene.heading, text: scene.text)
        if list.shots.contains(where: { $0.sceneID == scene.id }) {
            let alert = NSAlert()
            alert.messageText = L10n.string("Replace this scene's shots?", table: "Shots")
            alert.informativeText = L10n.string("Generation will replace existing shots for this scene only after it succeeds. Save a copy first to keep the current version.", table: "Shots")
            alert.addButton(withTitle: L10n.string("Generate and Replace", table: "Shots"))
            alert.addButton(withTitle: L10n.string("Cancel", table: "Shots"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        isGenerating = true
        status = L10n.string("Planning shots on your Mac…", table: "Shots")
        task = Task {
            defer { isGenerating = false; task = nil }
            do {
                let shots = try await LocalShotGenerator().generate(sceneID: scene.id, heading: scene.heading, source: scene.text, configuration: .init(executableURL: executableURL, modelURL: modelURL))
                try Task.checkCancellation()
                try list.replaceShots(for: anchor, with: shots)
                list.sourceFingerprint = SceneAnchor.digest(source)
                status = L10n.format(shots.count == 1 ? "Generated %d shot. Review and edit before saving." : "Generated %d shots. Review and edit before saving.", shots.count, table: "Shots")
            } catch is CancellationError { status = L10n.string("Generation cancelled. Existing shots preserved.", table: "Shots") }
            catch { self.error = error.localizedDescription; status = L10n.string("Generation failed. Existing shots preserved. Retry when ready.", table: "Shots") }
        }
    }

    func cancel() { task?.cancel() }

    private func write(to url: URL) throws {
        let data = try ShotListStore.data(for: list)
        try data.write(to: url, options: .atomic)
        fileURL = url
        baseline = data
        isDirty = false
        status = L10n.format("Saved %@", url.lastPathComponent, table: "Shots")
        persistRecovery()
    }

    private func persistRecovery() {
        guard let recoveryIdentity else { return }
        do { try recoveryStore.save(record: recoveryRecord, identity: recoveryIdentity) }
        catch { self.error = L10n.format("Could not save shot-list recovery: %@", error.localizedDescription, table: "Shots") }
    }

    func discardRecovery() {
        guard let recoveryIdentity else { return }
        do {
            try recoveryStore.discard(identity: recoveryIdentity)
            isDirty = false
        } catch { self.error = L10n.format("Could not discard shot-list recovery: %@", error.localizedDescription, table: "Shots") }
    }

    private func discardConfirmed() -> Bool {
        guard isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = L10n.string("Open another shot list?", table: "Shots")
        alert.informativeText = L10n.string("Current unsaved edits will be replaced. Save a copy first to keep them.", table: "Shots")
        alert.addButton(withTitle: L10n.string("Cancel", table: "Shots"))
        alert.addButton(withTitle: L10n.string("Discard and Open", table: "Shots"))
        return alert.runModal() == .alertSecondButtonReturn
    }
}

struct ShotWorkspace: View {
    @ObservedObject var document: FountainDocument
    @ObservedObject private var model: ShotWorkspaceModel
    @State private var showingSetup = false
    @State private var untitledIdentity = UUID().uuidString
    init(document: FountainDocument) {
        self.document = document
        self.model = document.shotWorkspace
    }

    private var screenplay: FountainScreenplay { FountainParser.parse(document.source) }
    private var scenes: [FountainScene] { screenplay.scenes }
    private var scene: FountainScene? { scenes.first { $0.id == model.selectedSceneID } ?? scenes.first }
    private var anchors: [SceneAnchor] { scenes.map { SceneAnchor(id: $0.id, heading: $0.heading, text: $0.text) } }
    private var visibleShots: [Shot] { model.list.shots.filter { $0.sceneID == scene?.id } }
    private var orphanedShots: [Shot] { model.list.shots.filter { shot in !scenes.contains { $0.id == shot.sceneID } } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Picker(L10n.string("Scene", table: "Shots"), selection: $model.selectedSceneID) {
                    Text(L10n.string("Scene", table: "Shots")).tag("")
                    ForEach(scenes, id: \.id) { scene in Text(scene.heading).tag(scene.id) }
                }.labelsHidden().frame(maxWidth: 420)
                if model.isDirty {
                    Circle().fill(.secondary).frame(width: 5, height: 5)
                        .help(L10n.string("Unsaved shot-list changes", table: "Shots")).accessibilityLabel(L10n.string("Unsaved shot-list changes", table: "Shots"))
                }
                Spacer()
                if model.isGenerating || model.isDownloading {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel(model.isGenerating ? L10n.string("Generating shots", table: "Shots") : L10n.string("Downloading model", table: "Shots"))
                    Button(L10n.string("Cancel", table: "Shots")) { model.cancel() }
                } else {
                    Button(L10n.string("Generate", table: "Shots")) {
                        if model.modelURL == nil || model.executableURL == nil { showingSetup = true }
                        else if let scene { model.generate(scene: scene, source: document.source) }
                    }.disabled(scene == nil)
                }
                Button {
                    if let scene { model.addShot(anchor: SceneAnchor(id: scene.id, heading: scene.heading, text: scene.text)) }
                } label: { Image(systemName: "plus") }
                .disabled(scene == nil || model.isGenerating).help(L10n.string("Add shot", table: "Shots")).accessibilityLabel(L10n.string("Add shot", table: "Shots"))
                Menu {
                    Button(L10n.string("Open shot list…", table: "Shots")) { model.open() }
                    Button(L10n.string("Save shot list", table: "Shots")) { model.save() }
                    Button(L10n.string("Save copy…", table: "Shots")) { model.save(asCopy: true) }
                    Divider()
                    Button(L10n.string("Local AI…", table: "Shots")) { showingSetup = true }
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel(L10n.string("Shot list actions", table: "Shots"))
            }.padding(.horizontal, 28).padding(.vertical, 16)
            if let scene, model.list.shots.contains(where: { $0.sceneID == scene.id }), model.list.linkState(for: scene.id, currentScenes: anchors) == .changed {
                Label(L10n.string("Scene changed. Review these shots.", table: "Shots"), systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).padding(.horizontal, 28).padding(.bottom, 12)
            }
            if scenes.isEmpty && orphanedShots.isEmpty {
                emptyState(L10n.string("Add a scene to your screenplay.", table: "Shots"))
            } else if visibleShots.isEmpty && orphanedShots.isEmpty {
                emptyState(L10n.string("No shots yet.", table: "Shots"))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach($model.list.shots) { $shot in
                            if shot.sceneID == scene?.id {
                                ShotRow(shot: $shot, number: (visibleShots.firstIndex(where: { $0.id == shot.id }) ?? 0) + 1) { model.removeShot(shot.id) }
                                    .disabled(model.isGenerating)
                                Divider().padding(.leading, 48)
                            }
                        }
                        if !orphanedShots.isEmpty {
                            Text(L10n.string("Unlinked shots", table: "Shots")).font(.callout).foregroundStyle(.secondary).padding(.top, 24)
                            ForEach($model.list.shots) { $shot in
                                if !scenes.contains(where: { $0.id == shot.sceneID }) {
                                    Text(model.list.anchors.first(where: { $0.id == shot.sceneID })?.heading ?? L10n.string("Scene missing", table: "Shots"))
                                        .font(.caption).foregroundStyle(.secondary).padding(.top, 12)
                                    ShotRow(shot: $shot, number: (orphanedShots.firstIndex(where: { $0.id == shot.id }) ?? 0) + 1) { model.removeShot(shot.id) }
                                        .disabled(model.isGenerating)
                                }
                            }
                        }
                    }.frame(maxWidth: 760).padding(.horizontal, 32).padding(.bottom, 32)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            model.prepare(source: document.source, name: document.fileURL?.deletingPathExtension().lastPathComponent, identity: document.fileURL?.path ?? "untitled:" + untitledIdentity)
            if model.selectedSceneID.isEmpty { model.selectedSceneID = scenes.first?.id ?? "" }
        }
        .onChange(of: scenes.map(\.id)) { _, ids in
            if !ids.contains(model.selectedSceneID) { model.selectedSceneID = ids.first ?? "" }
        }
        .alert(L10n.string("Shot list", table: "Shots"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button(L10n.string("OK", table: "Shots")) { model.error = nil } } message: { Text(model.error ?? "") }
        .sheet(isPresented: $showingSetup) { setupView }
    }

    private func emptyState(_ text: String) -> some View {
        VStack { Spacer(); Text(text).font(.custom("Courier", size: 15)).foregroundStyle(.tertiary); Spacer() }
            .frame(maxWidth: .infinity)
    }

    private var setupView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.string("Local AI", table: "Shots")).font(.title2).fontWeight(.semibold)
            Text(L10n.string("Runs offline after model download.", table: "Shots")).foregroundStyle(.secondary)
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.string("Runtime", table: "Shots")).font(.caption).foregroundStyle(.secondary)
                    Text(model.executableURL?.lastPathComponent ?? L10n.string("Not installed", table: "Shots"))
                        .help(model.executableURL?.path ?? L10n.string("Install llama.cpp to generate shots locally.", table: "Shots"))
                }
                Spacer()
                Button(L10n.string("Choose…", table: "Shots")) { model.chooseRuntime() }
            }
            if model.executableURL == nil {
                Text("brew install llama.cpp").font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string("Model", table: "Shots")).font(.caption).foregroundStyle(.secondary)
                Text(model.modelURL?.lastPathComponent ?? LocalModelStore.recommendedName).lineLimit(2)
                HStack {
                    Button(L10n.string("Choose model…", table: "Shots")) { model.chooseModel() }
                    if model.isDownloading {
                        ProgressView().controlSize(.small)
                        Button(L10n.string("Cancel", table: "Shots")) { model.cancel() }
                    } else {
                        Button(L10n.string("Download · 4.7 GB", table: "Shots")) { model.downloadModel() }.disabled(model.isGenerating)
                    }
                }
            }
            if model.isDownloading { Text(L10n.string("Downloading and verifying…", table: "Shots")).font(.caption).foregroundStyle(.secondary) }
            HStack { Spacer(); Button(L10n.string("Done", table: "Shots")) { showingSetup = false }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 460)
    }
}

private struct ShotRow: View {
    @Binding var shot: Shot
    let number: Int
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(String(format: "%02d", number))
                .font(.system(size: 13, design: .monospaced)).foregroundStyle(.tertiary).frame(width: 32).padding(.top, 3)
            VStack(alignment: .leading, spacing: 10) {
                TextField(L10n.string("Framing", table: "Shots"), text: $shot.framing)
                    .font(.custom("Courier-Bold", size: 15)).textFieldStyle(.plain).accessibilityLabel(L10n.format("Shot %d framing", number, table: "Shots"))
                TextField(L10n.string("Action", table: "Shots"), text: $shot.action, axis: .vertical)
                    .textFieldStyle(.plain).font(.custom("Courier", size: 15)).lineLimit(1...8).accessibilityLabel(L10n.format("Shot %d action", number, table: "Shots"))
                DisclosureGroup(L10n.string("Details", table: "Shots")) {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField(L10n.string("Camera movement", table: "Shots"), text: $shot.cameraMovement, axis: .vertical)
                            .accessibilityLabel(L10n.format("Shot %d camera movement", number, table: "Shots"))
                        TextField(L10n.string("Reason for this shot", table: "Shots"), text: $shot.rationale, axis: .vertical)
                            .accessibilityLabel(L10n.format("Shot %d rationale", number, table: "Shots"))
                    }.textFieldStyle(.plain).font(.callout).padding(.top, 8)
                }.font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 20)
            .contextMenu { Button(L10n.string("Delete shot", table: "Shots"), role: .destructive, action: remove) }
            .accessibilityAction(named: Text(L10n.string("Delete shot", table: "Shots")), remove)
    }
}
