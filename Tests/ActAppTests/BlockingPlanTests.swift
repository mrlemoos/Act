import ActCore
import AppKit
import Foundation
import Testing
import WebKit
@testable import Act

@Suite(.serialized) @MainActor
struct BlockingPlanTests {
    @MainActor private final class FilePanelFixture: NSObject, WKScriptMessageHandler {
        let bridge: BlockingPlanBridge
        weak var view: WKWebView?
        var exportedPNG: Data?
        init(bridge: BlockingPlanBridge) { self.bridge = bridge }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let id = body["id"] as? String else { return }
            var result: Any
            if body["action"] as? String == "reference" {
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                let red = NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)
                for x in 0..<2 { for y in 0..<2 { bitmap.setColor(red, atX: x, y: y) } }
                let png = bitmap.representation(using: .png, properties: [:])!
                result = ["id": "floor", "name": "Floor plan.png", "dataURL": "data:image/png;base64," + png.base64EncodedString(), "notes": ""]
            } else if body["action"] as? String == "export", let payload = body["payload"] as? [String: Any], let source = payload["dataURL"] as? String {
                exportedPNG = Data(base64Encoded: String(source.dropFirst("data:image/png;base64,".count)))
                result = true
            } else { bridge.userContentController(controller, didReceive: message); return }
            let data = try! JSONSerialization.data(withJSONObject: [id, result])
            view?.evaluateJavaScript("window.blocking.reply(...\(String(decoding: data, as: UTF8.self)))") { _, _ in }
        }
    }

    private func wait(_ view: WKWebView, until expression: String) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while ContinuousClock.now < deadline {
            if let result = try? await view.evaluateJavaScript(expression), result as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(30))
        }
        let error = try? await view.evaluateJavaScript("document.getElementById('error')?.textContent")
        Issue.record("Timed out waiting for \(expression). Editor error: \(String(describing: error))")
        throw NSError(domain: "BlockingPlanTests", code: 1)
    }

    @Test("The bundled editor generates, reviews, edits and recovers through the native bridge without changing Fountain or shots")
    func nativeWorkspaceRoundTrip() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ActBlocking-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = "INT. KITCHEN - DAY #1#\n\nMara waits beside a table.\n"
        let document = FountainDocument()
        document.aiReviewRecoveryDirectory = root
        try document.read(from: Data(source.utf8), ofType: "dev.act.fountain")
        let scene = try #require(document.screenplay.scenes.first)
        let anchor = SceneAnchor(id: scene.id, heading: scene.heading, text: scene.text)
        let shot = Shot(sceneID: scene.id, framing: "Wide", action: "Mara waits beside the table.", cameraMovement: "Static")
        let model = document.shotWorkspace
        model.automationRecoveryDirectory = root
        model.list = ShotListDocument(source: source, anchors: [anchor], shots: [shot])
        let originalShots = try ShotListStore.data(for: model.list)
        let geography: [String: Any] = ["items": [["kind": "actor", "label": "Mara", "x": 400, "y": 200, "width": 30, "height": 30]], "notes": "Proposed geography."]
        let cameras: [String: Any] = ["S1": ["camera": ["x": 100, "y": 450], "target": ["x": 415, "y": 215], "cameraEnd": NSNull(), "actors": [:], "warning": ""]]
        let first = root.appendingPathComponent("geography.json"), second = root.appendingPathComponent("overlays.json")
        try JSONSerialization.data(withJSONObject: geography).write(to: first)
        try JSONSerialization.data(withJSONObject: cameras).write(to: second)
        let runtime = root.appendingPathComponent("runtime")
        try "#!/bin/sh\ncase \"$*\" in *geography*) /bin/cat '\(first.path)' ;; *) /bin/cat '\(second.path)' ;; esac\n".write(to: runtime, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: runtime.path)
        let modelURL = root.appendingPathComponent("model.gguf")
        try Data("GGUFfixture".utf8).write(to: modelURL)
        model.executableURL = runtime; model.modelURL = modelURL
        let helper = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/act-blocking")
        #expect(FileManager.default.isExecutableFile(atPath: helper.path), "Build helpers with zsh scripts/build-cli.sh first")
        let url = try #require(BlockingPlanResources.editorURL)
        let bridge = BlockingPlanBridge(document: document, shots: model, sceneID: scene.id, recoveryDirectory: root, helperURL: helper, close: {})
        let configuration = WKWebViewConfiguration()
        let panels = FilePanelFixture(bridge: bridge)
        configuration.userContentController.add(panels, name: "blocking")
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1120, height: 820), configuration: configuration)
        bridge.webView = view; panels.view = view; view.navigationDelegate = bridge
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        defer { bridge.cancel(); view.configuration.userContentController.removeScriptMessageHandler(forName: "blocking"); window.contentView = nil; window.orderOut(nil) }
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        try await wait(view, until: "document.getElementById('shot')?.options.length === 1")
        try await view.evaluateJavaScript("document.getElementById('generate').click()")
        try await wait(view, until: "!!document.getElementById('accept')")
        #expect(try await view.evaluateJavaScript("document.getElementById('notice').textContent.includes('Draft proposal')") as? Bool == true)
        try await view.evaluateJavaScript("document.getElementById('accept').click()")
        try await wait(view, until: "!document.getElementById('accept') && !document.getElementById('save').disabled")
        // Keyboard selection and movement exercise the actual editor event path.
        try await view.evaluateJavaScript("document.querySelector('[data-key=\"item:actor-1\"]').dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowRight',bubbles:true})); true")
        #expect(try await view.evaluateJavaScript("document.querySelector('[data-key=\"item:actor-1\"] > g').getAttribute('transform') === 'translate(416 215)'") as? Bool == true)
        try await view.evaluateJavaScript("document.getElementById('facing').value='90'; document.getElementById('facing').dispatchEvent(new Event('change',{bubbles:true})); true")
        #expect(try await view.evaluateJavaScript("document.querySelector('[data-key=\"item:actor-1\"] g[transform=\"rotate(90)\"]') !== null") as? Bool == true)
        // Mock only native file panels; keep real SVG, canvas and embedded images.
        try await view.evaluateJavaScript("document.getElementById('reference').click()")
        try await wait(view, until: "!!document.querySelector('#references img')")
        try await view.evaluateJavaScript("document.getElementById('exportPNG').click()")
        let exportDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while panels.exportedPNG == nil, ContinuousClock.now < exportDeadline { try await Task.sleep(for: .milliseconds(20)) }
        let png = try #require(panels.exportedPNG)
        let bitmap = try #require(NSBitmapImageRep(data: png))
        #expect(bitmap.pixelsWide == 2800 && bitmap.pixelsHigh == 2125)
        let colour = try #require(bitmap.colorAt(x: 1400, y: 700)?.usingColorSpace(.deviceRGB))
        #expect(colour.redComponent > colour.greenComponent + 0.05, "Embedded reference should appear beneath the exported plan")
        let staleShot = model.list.shots[0]
        model.list.shots[0].action = "Mara moves."
        bridge.update()
        try await wait(view, until: "document.getElementById('notice').textContent.includes('changed')")
        model.list.shots[0] = staleShot
        #expect(document.source == source)
        #expect(try ShotListStore.data(for: model.list) == originalShots)
        let recoveryDir = root.appendingPathComponent("BlockingRecovery")
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while (try? FileManager.default.contentsOfDirectory(atPath: recoveryDir.path).isEmpty) != false, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        let recoveryFiles = try FileManager.default.contentsOfDirectory(at: recoveryDir, includingPropertiesForKeys: nil)
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: #require(recoveryFiles.first))) as! [String: Any]
        let session = try JSONSerialization.jsonObject(with: Data((saved["state"] as! String).utf8)) as! [String: Any]
        #expect(session["dirty"] as? Bool == true)
        #expect(session["plan"] is [String: Any])
        #expect(session["draft"] is NSNull)
        // A newly created native host must restore the edited accepted plan.
        let reopenedBridge = BlockingPlanBridge(document: document, shots: model, sceneID: scene.id, recoveryDirectory: root, helperURL: helper, close: {})
        let reopenedConfiguration = WKWebViewConfiguration()
        reopenedConfiguration.userContentController.add(reopenedBridge, name: "blocking")
        let reopened = WKWebView(frame: view.frame, configuration: reopenedConfiguration)
        reopenedBridge.webView = reopened; reopened.navigationDelegate = reopenedBridge
        window.contentView = reopened
        defer { reopened.configuration.userContentController.removeScriptMessageHandler(forName: "blocking") }
        reopened.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        try await wait(reopened, until: "document.querySelector('[data-key=\"item:actor-1\"] > g')?.getAttribute('transform') === 'translate(416 215)'")
        #expect(try await reopened.evaluateJavaScript("document.querySelector('[data-key=\"item:actor-1\"] g[transform=\"rotate(90)\"]') !== null") as? Bool == true)
        #expect(document.source == source)

    }
}
