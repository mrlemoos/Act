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
            status = recovered.isDirty ? "Recovered unsaved shot-list edits. Save to keep them." : "Reopened your shot list."
            if recovered.screenplayIdentity != identity {
                do { try recoveryStore.relocate(from: recovered.screenplayIdentity, to: identity, record: recoveryRecord) }
                catch { self.error = "Could not move recovered shot-list edits: \(error.localizedDescription)" }
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
        } catch { self.error = "Could not move shot-list recovery after saving your screenplay: \(error.localizedDescription)" }
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
                    error = "The shot-list file changed outside Act. Open it again to reload, or use Save Copy to preserve your edits separately."
                    return
                }
                try write(to: fileURL)
                return
            }
            let panel = NSSavePanel()
            panel.title = "Save shot list"
            panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "\(list.screenplayName ?? "Untitled").shots.json"
            panel.allowedContentTypes = [.json]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try write(to: url)
        } catch { self.error = error.localizedDescription }
    }

    func open() {
        guard !isGenerating, !isDownloading else { error = "Cancel the current operation before opening another shot list."; return }
        guard discardConfirmed() else { return }
        let panel = NSOpenPanel()
        panel.title = "Open shot list"
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
            status = "Opened \(url.lastPathComponent)"
            persistRecovery()
        } catch { self.error = error.localizedDescription }
    }

    func chooseModel() {
        let panel = NSOpenPanel()
        panel.title = "Choose a GGUF model"
        panel.message = "Choose a local instruct model supported by llama.cpp. No screenplay text leaves your Mac."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.pathExtension.lowercased() == "gguf" else { error = "Choose a GGUF model file."; return }
        modelURL = url
        UserDefaults.standard.set(url.path, forKey: "Act.localModelPath")
    }

    func chooseRuntime() {
        let panel = NSOpenPanel()
        panel.title = "Choose llama.cpp runtime"
        panel.message = "Select the llama.cpp llama-completion or llama-cli executable. It runs locally using your Mac's GPU."
        panel.showsHiddenFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard FileManager.default.isExecutableFile(atPath: url.path) else { error = "Choose an executable llama-cli binary."; return }
        executableURL = url
        UserDefaults.standard.set(url.path, forKey: "Act.localRuntimePath")
    }

    func downloadModel() {
        guard !isDownloading else { return }
        isDownloading = true
        status = "Downloading and verifying the model. Screenplay text stays on this Mac."
        task = Task {
            defer { isDownloading = false; task = nil }
            do {
                let url = try await modelStore.download()
                modelURL = url
                UserDefaults.standard.set(url.path, forKey: "Act.localModelPath")
                status = "Model ready. Generation works offline."
            } catch is CancellationError { status = "Download cancelled." }
            catch where Task.isCancelled { status = "Download cancelled." }
            catch { self.error = error.localizedDescription; status = "Model download failed. You can retry." }
        }
    }

    func generate(scene: FountainScene, source: String) {
        guard !isGenerating, !isDownloading else { return }
        guard let executableURL, let modelURL else { error = "Choose a local runtime and model first."; return }
        let anchor = SceneAnchor(id: scene.id, heading: scene.heading, text: scene.text)
        if list.shots.contains(where: { $0.sceneID == scene.id }) {
            let alert = NSAlert()
            alert.messageText = "Replace this scene's shots?"
            alert.informativeText = "Generation will replace existing shots for this scene only after it succeeds. Save a copy first to keep the current version."
            alert.addButton(withTitle: "Generate and Replace")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        isGenerating = true
        status = "Planning shots on your Mac…"
        task = Task {
            defer { isGenerating = false; task = nil }
            do {
                let shots = try await LocalShotGenerator().generate(sceneID: scene.id, heading: scene.heading, source: scene.text, configuration: .init(executableURL: executableURL, modelURL: modelURL))
                try Task.checkCancellation()
                try list.replaceShots(for: anchor, with: shots)
                list.sourceFingerprint = SceneAnchor.digest(source)
                status = "Generated \(shots.count) shots. Review and edit before saving."
            } catch is CancellationError { status = "Generation cancelled. Existing shots preserved." }
            catch { self.error = error.localizedDescription; status = "Generation failed. Existing shots preserved. Retry when ready." }
        }
    }

    func cancel() { task?.cancel() }

    private func write(to url: URL) throws {
        let data = try ShotListStore.data(for: list)
        try data.write(to: url, options: .atomic)
        fileURL = url
        baseline = data
        isDirty = false
        status = "Saved \(url.lastPathComponent)"
        persistRecovery()
    }

    private func persistRecovery() {
        guard let recoveryIdentity else { return }
        do { try recoveryStore.save(record: recoveryRecord, identity: recoveryIdentity) }
        catch { self.error = "Could not save shot-list recovery: \(error.localizedDescription)" }
    }

    func discardRecovery() {
        guard let recoveryIdentity else { return }
        do {
            try recoveryStore.discard(identity: recoveryIdentity)
            isDirty = false
        } catch { self.error = "Could not discard shot-list recovery: \(error.localizedDescription)" }
    }

    private func discardConfirmed() -> Bool {
        guard isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Open another shot list?"
        alert.informativeText = "Current unsaved edits will be replaced. Save a copy first to keep them."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard and Open")
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
                Picker("Scene", selection: $model.selectedSceneID) {
                    Text("Scene").tag("")
                    ForEach(scenes, id: \.id) { scene in Text(scene.heading).tag(scene.id) }
                }.labelsHidden().frame(maxWidth: 420)
                if model.isDirty {
                    Circle().fill(.secondary).frame(width: 5, height: 5)
                        .help("Unsaved shot-list changes").accessibilityLabel("Unsaved shot-list changes")
                }
                Spacer()
                if model.isGenerating || model.isDownloading {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel(model.isGenerating ? "Generating shots" : "Downloading model")
                    Button("Cancel") { model.cancel() }
                } else {
                    Button("Generate") {
                        if model.modelURL == nil || model.executableURL == nil { showingSetup = true }
                        else if let scene { model.generate(scene: scene, source: document.source) }
                    }.disabled(scene == nil)
                }
                Button {
                    if let scene { model.addShot(anchor: SceneAnchor(id: scene.id, heading: scene.heading, text: scene.text)) }
                } label: { Image(systemName: "plus") }
                .disabled(scene == nil || model.isGenerating).help("Add shot").accessibilityLabel("Add shot")
                Menu {
                    Button("Open shot list…") { model.open() }
                    Button("Save shot list") { model.save() }
                    Button("Save copy…") { model.save(asCopy: true) }
                    Divider()
                    Button("Local AI…") { showingSetup = true }
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Shot list actions")
            }.padding(.horizontal, 28).padding(.vertical, 16)
            if let scene, model.list.shots.contains(where: { $0.sceneID == scene.id }), model.list.linkState(for: scene.id, currentScenes: anchors) == .changed {
                Label("Scene changed. Review these shots.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).padding(.horizontal, 28).padding(.bottom, 12)
            }
            if scenes.isEmpty && orphanedShots.isEmpty {
                emptyState("Add a scene to your screenplay.")
            } else if visibleShots.isEmpty && orphanedShots.isEmpty {
                emptyState("No shots yet.")
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
                            Text("Unlinked shots").font(.callout).foregroundStyle(.secondary).padding(.top, 24)
                            ForEach($model.list.shots) { $shot in
                                if !scenes.contains(where: { $0.id == shot.sceneID }) {
                                    Text(model.list.anchors.first(where: { $0.id == shot.sceneID })?.heading ?? "Scene missing")
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
        .alert("Shot list", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
        .sheet(isPresented: $showingSetup) { setupView }
    }

    private func emptyState(_ text: String) -> some View {
        VStack { Spacer(); Text(text).font(.custom("Courier", size: 15)).foregroundStyle(.tertiary); Spacer() }
            .frame(maxWidth: .infinity)
    }

    private var setupView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Local AI").font(.title2).fontWeight(.semibold)
            Text("Runs offline after model download.").foregroundStyle(.secondary)
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Runtime").font(.caption).foregroundStyle(.secondary)
                    Text(model.executableURL?.lastPathComponent ?? "Not installed")
                        .help(model.executableURL?.path ?? "Install llama.cpp to generate shots locally.")
                }
                Spacer()
                Button("Choose…") { model.chooseRuntime() }
            }
            if model.executableURL == nil {
                Text("brew install llama.cpp").font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("Model").font(.caption).foregroundStyle(.secondary)
                Text(model.modelURL?.lastPathComponent ?? LocalModelStore.recommendedName).lineLimit(2)
                HStack {
                    Button("Choose model…") { model.chooseModel() }
                    if model.isDownloading {
                        ProgressView().controlSize(.small)
                        Button("Cancel") { model.cancel() }
                    } else {
                        Button("Download · 4.7 GB") { model.downloadModel() }.disabled(model.isGenerating)
                    }
                }
            }
            if model.isDownloading { Text("Downloading and verifying…").font(.caption).foregroundStyle(.secondary) }
            HStack { Spacer(); Button("Done") { showingSetup = false }.keyboardShortcut(.defaultAction) }
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
                TextField("Framing", text: $shot.framing)
                    .font(.custom("Courier-Bold", size: 15)).textFieldStyle(.plain).accessibilityLabel("Shot \(number) framing")
                TextField("Action", text: $shot.action, axis: .vertical)
                    .textFieldStyle(.plain).font(.custom("Courier", size: 15)).lineLimit(1...8).accessibilityLabel("Shot \(number) action")
                DisclosureGroup("Details") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Camera movement", text: $shot.cameraMovement, axis: .vertical)
                            .accessibilityLabel("Shot \(number) camera movement")
                        TextField("Reason for this shot", text: $shot.rationale, axis: .vertical)
                            .accessibilityLabel("Shot \(number) rationale")
                    }.textFieldStyle(.plain).font(.callout).padding(.top, 8)
                }.font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 20)
            .contextMenu { Button("Delete shot", role: .destructive, action: remove) }
            .accessibilityAction(named: Text("Delete shot"), remove)
    }
}
