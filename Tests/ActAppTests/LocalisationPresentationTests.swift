import ActCore
import AppKit
import SwiftUI
import Testing
import Vision
@testable import Act

/// Opt-in, per-process language checks never alter the user's saved language preferences.
@Suite(.serialized)
@MainActor
struct LocalisationPresentationTests {
    @Test func nativeLanguageMenusAndWorkspaceRenders() async throws {
        guard let expected = ProcessInfo.processInfo.environment["ACT_TEST_EXPECTED_LANGUAGE"] else { return }
        let originalArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = originalArguments
        arguments["AppleLanguages"] = [expected]
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(originalArguments, forName: UserDefaults.argumentDomain) }
        #expect(L10n.language == expected)

        let application = NSApplication.shared
        let originalMenu = application.mainMenu
        let originalWindowMenu = application.windowsMenu
        defer { application.mainMenu = originalMenu; application.windowsMenu = originalWindowMenu }
        let delegate = ActApplicationDelegate()
        delegate.installMainMenu()
        let fileMenu = try #require(application.mainMenu?.items.dropFirst().first?.submenu)
        let expectedFileTitles = ["en-GB": "File", "en-US": "File", "pt-BR": "Arquivo", "es-ES": "Archivo", "fr-FR": "Fichier", "de-DE": "Ablage", "it-IT": "File"]
        #expect(fileMenu.title == expectedFileTitles[expected])
        #expect(fileMenu.items.first(where: { $0.keyEquivalent == "s" })?.title == L10n.string("Save", table: "Menus"))
        #expect(fileMenu.items.first(where: { $0.keyEquivalent == "o" })?.action == #selector(NSDocumentController.openDocument(_:)))

        guard let path = ProcessInfo.processInfo.environment["ACT_TEST_LOCALISATION_DIRECTORY"] else { return }
        let output = URL(fileURLWithPath: path).appendingPathComponent(expected)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("ActLocalisation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let suite = "ActLocalisation-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = WritingPreferences(defaults: defaults)
        let source = "# A new beginning\n\nINT. CAFÉ - DAY\n\nMARA wears a blue coat.\n\nMARA\nStay for coffee.\n"
        let document = FountainDocument()
        try document.read(from: Data(source.utf8), ofType: "dev.act.fountain")
        document.characterWorkspace.prepare(screenplayURL: temporary.appendingPathComponent("Café.fountain"), source: source)
        #expect(document.characterWorkspace.mark(selection: (source as NSString).range(of: "MARA")))
        document.ensureProjectBoard()
        document.projectBoard?.change("Layout fixture") { board in
            board.cards.append(BoardCard(kind: .note, title: "User content: café", position: BoardPoint(x: 80, y: 80)))
        }
        let preview = ScreenplayPreviewModel(document: document, preferences: preferences)
        #expect(preview.pdf != nil)
        for (suffix, size, appearance) in [
            ("desktop-light", NSSize(width: 1280, height: 900), NSAppearance.Name.aqua),
            ("narrow-dark", NSSize(width: 820, height: 700), NSAppearance.Name.darkAqua)
        ] {
            for section in [WorkspaceSection.screenplay, .shots, .characters, .board] {
                document.requestedWorkspace = nil
                document.showsSettings = false
                try await render(WorkspaceView(document: document, preferences: preferences, initialWorkspace: section), size: size, appearance: appearance,
                           to: output.appendingPathComponent("\(section.rawValue)-\(suffix).png"))
            }
            document.requestedWorkspace = nil
            document.showsSettings = true
            try await render(WorkspaceView(document: document, preferences: preferences), size: size, appearance: appearance,
                       to: output.appendingPathComponent("settings-\(suffix).png"))
            document.showsSettings = false
            // PDFKit's layer-backed content cannot be captured reliably with cacheDisplay.
            // Capture the actual shared toolbar separately; full PDF preview requires desktop inspection.
            try await render(ScreenplayPreviewToolbar(document: document, model: preview), size: NSSize(width: size.width, height: 64), appearance: appearance,
                       to: output.appendingPathComponent("preview-toolbar-\(suffix).png"), previewToolbar: true)
        }
        try await render(ScreenplayPreviewToolbar(document: document, model: preview), size: NSSize(width: 580, height: 64), appearance: .aqua,
                   to: output.appendingPathComponent("preview-toolbar-minimum-light.png"), previewToolbar: true)
        #expect(document.source == source, "Localising and rendering never rewrites screenplay content")
        try fileMenu.items.filter { !$0.isSeparatorItem }.map { "\($0.title)\t\($0.keyEquivalent)" }.joined(separator: "\n")
            .write(to: output.appendingPathComponent("menus.txt"), atomically: true, encoding: .utf8)
    }

    private func render<Content: View>(_ content: Content, size: NSSize, appearance: NSAppearance.Name, to url: URL, previewToolbar: Bool = false) async throws {
        let view = NSHostingView(rootView: content.background(Color(nsColor: .windowBackgroundColor)))
        view.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = view
        view.frame = NSRect(origin: .zero, size: size)
        defer { window.contentView = nil; window.close() }
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        view.layoutSubtreeIfNeeded()
        #expect(view.frame.size == size, "The actual workspace must fit its requested window")
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
        if previewToolbar {
            // SwiftUI exposes no AX children in this hidden test host. OCR verifies actual visible control text;
            // accessibility semantics and the complete PDF preview are checked in the running app separately.
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.automaticallyDetectsLanguage = true
            try VNImageRequestHandler(cgImage: try #require(bitmap.cgImage)).perform([request])
            let observations = request.results ?? []
            for key in ["Paper", "Export PDF…", "Print…"] {
                let label = L10n.string(key, table: "Writing")
                let control = try #require(observations.first { observation in
                    observation.topCandidates(1).contains { normalise($0.string).contains(normalise(label)) }
                }, "Missing visible translated preview control: \(label)")
                #expect(control.boundingBox.width > 0 && control.boundingBox.height > 0)
                #expect(CGRect(x: 0, y: 0, width: 1, height: 1).contains(control.boundingBox), "\(label) fits at \(size.width) points")
            }
        }
    }

    private func normalise(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: L10n.language))
            .filter { $0.isLetter || $0.isNumber }
    }
}
