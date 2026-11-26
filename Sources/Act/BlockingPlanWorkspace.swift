import ActCore
import AppKit
import CryptoKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct BlockingPlanWorkspace: View {
    @ObservedObject var document: FountainDocument
    @ObservedObject var shots: ShotWorkspaceModel
    let sceneID: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        BlockingPlanWebView(document: document, shots: shots, sceneID: sceneID, close: { dismiss() })
            .frame(minWidth: 850, idealWidth: 1120, minHeight: 650, idealHeight: 820)
            .interactiveDismissDisabled()
    }
}

private struct BlockingPlanWebView: NSViewRepresentable {
    @ObservedObject var document: FountainDocument
    @ObservedObject var shots: ShotWorkspaceModel
    let sceneID: String
    let close: () -> Void

    func makeCoordinator() -> BlockingPlanBridge { BlockingPlanBridge(document: document, shots: shots, sceneID: sceneID, close: close) }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "blocking")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        context.coordinator.webView = view
        if let url = BlockingPlanResources.editorURL { view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent()) }
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) { context.coordinator.update() }
    static func dismantleNSView(_ view: WKWebView, coordinator: BlockingPlanBridge) {
        coordinator.cancel()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "blocking")
    }
}

private struct BlockingRecovery: Codable {
    var state: String
    var path: String?
    var baseline: Data?
    var dirty: Bool
}

@MainActor
final class BlockingPlanBridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    weak var webView: WKWebView?
    private let document: FountainDocument
    private let shots: ShotWorkspaceModel
    private let sceneID: String
    private let close: () -> Void
    private let recoveryURL: URL
    private let helperURL: URL?
    private var recovery: BlockingRecovery?
    private var initialError: String?
    private var fileURL: URL?
    private var baseline: Data?
    private var dirty = false
    private var ready = false
    private var lastScene = Data()
    private var pendingOpen: (token: String, url: URL, data: Data)?
    private var run: BlockingHelperRun?

    init(document: FountainDocument, shots: ShotWorkspaceModel, sceneID: String, recoveryDirectory: URL? = nil, helperURL: URL? = nil, close: @escaping () -> Void) {
        self.document = document; self.shots = shots; self.sceneID = sceneID; self.close = close
        self.helperURL = helperURL
        let identity = (document.fileURL?.path ?? "untitled:\(document.automationID)") + "\n" + sceneID
        let hash = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        let root = recoveryDirectory ?? ProcessInfo.processInfo.environment["ACT_AUTOMATION_DIRECTORY"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Act")
        recoveryURL = root.appendingPathComponent("BlockingRecovery/\(hash).json")
        super.init()
        if FileManager.default.fileExists(atPath: recoveryURL.path) {
            do {
                let data = try Data(contentsOf: recoveryURL)
                guard data.count <= 32_000_000 else { throw BlockingBridgeError.message("Blocking-plan recovery exceeds its size limit.") }
                recovery = try JSONDecoder().decode(BlockingRecovery.self, from: data)
                fileURL = recovery?.path.map { URL(fileURLWithPath: $0) }; baseline = recovery?.baseline; dirty = recovery?.dirty ?? false
            } catch { initialError = "Could not restore blocking-plan recovery: \(error.localizedDescription)" }
        }
    }

    private func sceneData() throws -> [String: Any] {
        guard let scene = document.screenplay.scenes.first(where: { $0.id == sceneID }) else {
            throw BlockingBridgeError.message("This scene is missing. Existing plan retained; reopen its scene to generate again.")
        }
        let encoder = JSONEncoder()
        let shotData = try encoder.encode(shots.list.shots.filter { $0.sceneID == sceneID })
        return ["sceneID": scene.id, "heading": scene.heading, "source": scene.text,
                "shots": try JSONSerialization.jsonObject(with: shotData)]
    }
    func update() {
        guard ready else { return }
        do {
            let scene = try sceneData()
            let data = try JSONSerialization.data(withJSONObject: scene, options: [.sortedKeys])
            guard data != lastScene else { return }
            lastScene = data
            evaluate("window.blocking.update(\(String(decoding: data, as: UTF8.self)))")
        } catch { evaluate("window.blocking.invalidate(\(literal(error.localizedDescription)))") }
    }
    private func literal(_ value: String) -> String {
        let data = try! JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }
    private func evaluate(_ code: String) { webView?.evaluateJavaScript(code) { _, _ in } }
    private func reply(_ id: String, _ value: Any = NSNull(), error: String? = nil) {
        let data = (try? JSONSerialization.data(withJSONObject: [id, value, error as Any? ?? NSNull()], options: [.fragmentsAllowed])) ?? Data("[]".utf8)
        evaluate("window.blocking.reply(...\(String(decoding: data, as: UTF8.self)))")
    }
    func cancel() { run?.cancel() }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.isFileURL == true,
              let body = message.body as? [String: Any], let id = body["id"] as? String,
              let action = body["action"] as? String else { return }
        let payload = body["payload"] as? [String: Any] ?? [:]
        do {
            switch action {
            case "ready":
                var context: [String: Any] = ["scene": try sceneData(), "runtime": shots.executableURL?.path as Any? ?? NSNull(),
                                             "model": shots.modelURL?.path as Any? ?? NSNull(), "recovery": recovery?.state as Any? ?? NSNull()]
                if let initialError { context["initialError"] = initialError }
                let data = try JSONSerialization.data(withJSONObject: context)
                evaluate("window.blocking.start(\(String(decoding: data, as: UTF8.self)))")
                ready = true; update(); reply(id, true)
            case "recovery":
                dirty = payload["dirty"] as? Bool ?? true
                guard let state = payload["state"] as? String, state.utf8.count <= 24_000_000 else { throw BlockingBridgeError.message("Blocking-plan recovery exceeds its size limit.") }
                let record = BlockingRecovery(state: state, path: fileURL?.path, baseline: baseline, dirty: dirty)
                try FileManager.default.createDirectory(at: recoveryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(record).write(to: recoveryURL, options: .atomic)
                recovery = record; reply(id, true)
            case "open":
                guard confirmLeaving() else { reply(id); return }
                let panel = NSOpenPanel(); panel.title = "Open overhead blocking plan"; panel.allowedContentTypes = [.json]
                guard panel.runModal() == .OK, let url = panel.url else { reply(id); return }
                let data = try boundedRead(url, limit: 12_000_000)
                guard let content = String(data: data, encoding: .utf8) else { throw BlockingBridgeError.message("Plan must contain UTF-8 JSON.") }
                let token = UUID().uuidString; pendingOpen = (token, url, data)
                reply(id, ["token": token, "content": content])
            case "adoptOpen":
                guard let opened = pendingOpen, payload["token"] as? String == opened.token else { throw BlockingBridgeError.message("Open request expired. Choose the plan again.") }
                fileURL = opened.url; baseline = opened.data; pendingOpen = nil; dirty = false; reply(id, true)
            case "save":
                guard let content = payload["content"] as? String, content.utf8.count <= 12_000_000 else { throw BlockingBridgeError.message("Invalid or oversized blocking plan.") }
                reply(id, try save(Data(content.utf8)))
            case "reference": reply(id, try chooseReference() ?? NSNull())
            case "export": reply(id, try export(payload))
            case "generate": try generate(id: id, payload: payload)
            case "cancel": cancel(); reply(id, true)
            case "done":
                // Changes are recovered automatically; closing does not discard them.
                cancel(); close(); reply(id, true)
            default: throw BlockingBridgeError.message("Unsupported blocking-plan action.")
            }
        } catch { reply(id, error: error.localizedDescription) }
    }

    private func confirmLeaving() -> Bool {
        guard !dirty else {
            let alert = NSAlert(); alert.messageText = "Open another plan?"; alert.informativeText = "Save your current plan first to keep its unsaved changes. Opening another plan replaces this scene's recovered workspace."
            alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Open Another Plan")
            return alert.runModal() == .alertSecondButtonReturn
        }
        return true
    }
    private func boundedRead(_ url: URL, limit: Int) throws -> Data {
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? Int.max
        guard size <= limit else { throw BlockingBridgeError.message("File exceeds the supported size limit.") }
        let data = try Data(contentsOf: url)
        guard data.count <= limit else { throw BlockingBridgeError.message("File exceeds the supported size limit.") }
        return data
    }
    private func save(_ data: Data) throws -> Bool {
        var destination = fileURL
        if let url = destination, (try? Data(contentsOf: url)) != baseline {
            let alert = NSAlert(); alert.messageText = "Blocking plan changed outside Act"; alert.informativeText = "Open it again to reload, or save a copy to preserve your edits separately."
            alert.addButton(withTitle: "Save Copy…"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return false }; destination = nil
        }
        if destination == nil {
            let panel = NSSavePanel(); panel.title = "Save overhead blocking plan"; panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "Scene.blocking.json"
            panel.directoryURL = fileURL?.deletingLastPathComponent() ?? shots.fileURL?.deletingLastPathComponent() ?? document.fileURL?.deletingLastPathComponent()
            guard panel.runModal() == .OK, let url = panel.url else { return false }; destination = url
        }
        guard let destination else { return false }
        try data.write(to: destination, options: .atomic)
        fileURL = destination; baseline = data; dirty = false
        return true
    }
    private func chooseReference() throws -> [String: Any]? {
        let panel = NSOpenPanel(); panel.title = "Choose floor plan or location photograph"; panel.allowedContentTypes = [.png, .jpeg]
        panel.message = "Images guide manual placement. The local text model uses geometry notes, not image contents. Maximum 2 MB per image."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let data = try boundedRead(url, limit: 2_000_000)
        guard let image = NSBitmapImageRep(data: data), image.pixelsWide <= 16000, image.pixelsHigh <= 16000 else { throw BlockingBridgeError.message("Choose a valid PNG or JPEG no larger than 16,000 pixels per side.") }
        let isPNG = data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10])
        guard isPNG || data.starts(with: [255, 216, 255]) else { throw BlockingBridgeError.message("Choose a PNG or JPEG image.") }
        return ["id": UUID().uuidString, "name": url.lastPathComponent, "notes": "", "dataURL": "data:image/\(isPNG ? "png" : "jpeg");base64," + data.base64EncodedString()]
    }
    private func export(_ payload: [String: Any]) throws -> Bool {
        guard let format = payload["format"] as? String, ["png", "pdf"].contains(format),
              let source = payload["dataURL"] as? String, source.hasPrefix("data:image/png;base64,"), source.count <= 32_000_000,
              let data = Data(base64Encoded: String(source.dropFirst("data:image/png;base64,".count))),
              let image = NSImage(data: data) else { throw BlockingBridgeError.message("Could not render the plan export.") }
        let panel = NSSavePanel(); panel.title = "Export selected shot plan"; panel.allowedContentTypes = format == "pdf" ? [.pdf] : [.png]
        panel.nameFieldStringValue = "Blocking-Shot-\(payload["shotNumber"] as? Int ?? 1).\(format)"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        if format == "png" { try data.write(to: url, options: .atomic) }
        else {
            let view = NSImageView(frame: NSRect(x: 0, y: 0, width: 840, height: 637.5))
            view.image = image; view.imageScaling = .scaleProportionallyUpOrDown
            try view.dataWithPDF(inside: view.bounds).write(to: url, options: .atomic)
        }
        return true
    }
    private func generate(id: String, payload: [String: Any]) throws {
        guard run == nil else { throw BlockingBridgeError.message("The previous local generation is still stopping. Retry in a moment.") }
        guard let runtime = shots.executableURL, let model = shots.modelURL else { throw BlockingBridgeError.message("Choose a local runtime and model in Local AI first.") }
        guard let app = Bundle.main.executableURL?.deletingLastPathComponent().deletingLastPathComponent() else { throw BlockingBridgeError.message("Open the packaged Act app to generate blocking plans.") }
        let helper = helperURL ?? app.appendingPathComponent("Helpers/act-blocking")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else { throw BlockingBridgeError.message("Blocking-plan helper is missing. Rebuild or reinstall Act.") }
        var input = payload; input["runtime"] = runtime.path; input["model"] = model.path
        let data = try JSONSerialization.data(withJSONObject: input)
        guard data.count <= 128000 else { throw BlockingBridgeError.message("Scene and shot data exceed the generation limit.") }
        let process = BlockingHelperRun(); run = process
        Task { [weak self] in
            do {
                let result = try await Task.detached { try process.execute(helper: helper, input: data) }.value
                guard let self else { return }
                self.run = nil
                let value = try JSONSerialization.jsonObject(with: result)
                self.reply(id, value)
            } catch { guard let self else { return }; self.run = nil; self.reply(id, error: error.localizedDescription) }
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        let allowed = navigationAction.request.url == BlockingPlanResources.editorURL
        decisionHandler(allowed ? .allow : .cancel)
    }
}

private enum BlockingBridgeError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let message): message } }
}

private final class BlockingHelperRun: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    func cancel() {
        lock.lock(); cancelled = true; let running = process; lock.unlock()
        if let running, running.isRunning { running.terminate() }
    }
    func execute(helper: URL, input: Data) throws -> Data {
        let child = Process(), stdin = Pipe(), stdout = Pipe()
        child.executableURL = helper; child.standardInput = stdin; child.standardOutput = stdout
        child.standardError = FileHandle.nullDevice
        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        do { try child.run(); process = child; lock.unlock() } catch { lock.unlock(); throw error }
        defer { lock.lock(); process = nil; lock.unlock() }
        try stdin.fileHandleForWriting.write(contentsOf: input); try stdin.fileHandleForWriting.close()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        child.waitUntilExit()
        guard data.count <= 1_000_000 else { throw BlockingBridgeError.message("Local plan output exceeded its limit.") }
        guard !data.isEmpty else { throw BlockingBridgeError.message("Local generation stopped without a result. Existing plan preserved.") }
        return data
    }
}
