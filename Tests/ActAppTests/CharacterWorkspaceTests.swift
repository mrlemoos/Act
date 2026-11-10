import ActCore
import AppKit
import SwiftUI
import Testing
@testable import Act

@Suite(.serialized) @MainActor
struct CharacterWorkspaceTests {
    @Test func nativeMarkPersistsColourWithoutChangingSourceCaretOrUndo() throws {
        let source = "INT. ROOM - DAY\r\n\r\nA man with calloused hands is ORLEANS."
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = try TestEditorHost(source: source)
        defer { host.close() }
        let screenplayURL = directory.appendingPathComponent("Draft.fountain")
        host.document.fileURL = screenplayURL
        let range = (source as NSString).range(of: "ORLEANS")
        host.textView.setSelectedRange(range)
        let text = try #require(host.textView as? ScreenplayTextView)
        text.markCharacter(NSMenuItem())
        host.coordinator.format()
        #expect(host.document.source == source)
        #expect(host.textView.string == source)
        #expect(host.textView.selectedRange() == range)
        #expect(host.document.undoManager?.canUndo == false)
        #expect(host.document.characterWorkspace.library.characters.count == 1)
        #expect(host.textView.textStorage?.attribute(.backgroundColor, at: range.location, effectiveRange: nil) != nil)
        let manifest = CharacterLibraryStore.directory(for: screenplayURL).appendingPathComponent("characters.json")
        let loaded = try CharacterLibraryStore.decode(Data(contentsOf: manifest))
        #expect(loaded.characters[0].marks[0].paragraph == "A man with calloused hands is ORLEANS.")
    }

    @Test func promptAndVersionsSurviveReopeningAndParagraphChanges() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let screenplay = directory.appendingPathComponent("Draft.fountain")
        let source = "ORLEANS has calloused hands."
        let model = CharacterWorkspaceModel()
        model.prepare(screenplayURL: screenplay, source: source)
        #expect(model.mark(selection: (source as NSString).range(of: "ORLEANS")))
        model.library.characters[0].prompt = "Custom direction"
        model.library.characters[0].marks[0].extractedParagraph = source
        let version = CharacterSheetVersion(imageFile: "images/a.png", prompt: "Original prompt", agent: "grok")
        model.library.characters[0].versions.append(version)
        model.library.characters[0].activeVersionID = version.id
        model.save()
        let reopened = CharacterWorkspaceModel()
        reopened.prepare(screenplayURL: screenplay, source: source)
        #expect(reopened.library.characters[0].prompt == "Custom direction")
        #expect(reopened.library.characters[0].versions == [version])
        reopened.updateSource(source.replacingOccurrences(of: "calloused", with: "scarred"))
        #expect(reopened.library.characters[0].needsReview)
        #expect(reopened.library.characters[0].prompt == "Custom direction")
        #expect(reopened.library.characters[0].versions == [version])
        reopened.save()
    }

    @Test func externalLibraryChangePreventsOverwrite() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let screenplay = directory.appendingPathComponent("Draft.fountain")
        let model = CharacterWorkspaceModel()
        model.prepare(screenplayURL: screenplay, source: "ORLEANS waits.")
        #expect(model.mark(selection: NSRange(location: 0, length: 7)))
        let manifest = try #require(model.directory).appendingPathComponent("characters.json")
        let external = Data("external edit".utf8)
        try external.write(to: manifest)
        model.library.characters[0].prompt = "Unsaved user prompt"
        model.save()
        #expect(model.isDirty)
        #expect(model.error == CharacterSheetError.externalChange.localizedDescription)
        #expect(try Data(contentsOf: manifest) == external)
    }

    @Test func saveAsCopiesAssetsAndKeepsOriginalLibrary() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = directory.appendingPathComponent("First.fountain"), new = directory.appendingPathComponent("Second.fountain")
        let model = CharacterWorkspaceModel()
        model.prepare(screenplayURL: old, source: "ORLEANS waits.")
        #expect(model.mark(selection: NSRange(location: 0, length: 7)))
        model.library.characters[0].prompt = "Keep me"
        model.save()
        let original = try #require(model.directory)
        model.prepare(screenplayURL: new, source: "ORLEANS waits.")
        #expect(model.directory == CharacterLibraryStore.directory(for: new))
        #expect(FileManager.default.fileExists(atPath: original.appendingPathComponent("characters.json").path))
        #expect(model.library.characters[0].prompt == "Keep me")
    }

    @Test func extractionPreservesEditedPromptAndRejectsChangedParagraphDuringInference() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("mlx_lm.generate")
        try """
        #!/bin/sh
        /bin/cat >/dev/null
        /bin/sleep 0.15
        printf '%s' '{"traits":[{"attribute":"hands","value":"calloused","evidence":"calloused hands"}]}'
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        try Data("{}".utf8).write(to: directory.appendingPathComponent("config.json"))
        try Data().write(to: directory.appendingPathComponent("model.safetensors"))
        let source = "ORLEANS has calloused hands."
        let model = CharacterWorkspaceModel()
        model.prepare(screenplayURL: directory.appendingPathComponent("Draft.fountain"), source: source)
        model.mlxExecutable = executable; model.mlxModel = directory
        #expect(model.mark(selection: NSRange(location: 0, length: 7)))
        let id = try #require(model.selectedID)
        model.updatePrompt("My custom prompt", id: id)
        model.extract(id: id)
        for _ in 0..<500 { if !model.isBusy { break }; try await Task.sleep(for: .milliseconds(10)) }
        #expect(!model.isBusy)
        #expect(model.library.characters[0].marks[0].traits.first?.value == "calloused")
        #expect(model.library.characters[0].prompt == "My custom prompt")
        let evidence = model.library.characters[0].marks[0].traits
        model.extract(id: id)
        model.updateSource(source.replacingOccurrences(of: "calloused", with: "scarred"))
        for _ in 0..<500 { if !model.isBusy { break }; try await Task.sleep(for: .milliseconds(10)) }
        #expect(!model.isBusy)
        #expect(model.error?.contains("changed during extraction") == true)
        #expect(model.library.characters[0].marks[0].traits == evidence)
        #expect(model.library.characters[0].needsReview)
        #expect(model.library.characters[0].prompt == "My custom prompt")
        model.save()
    }

    @Test func renderActualCharacterWorkspaceWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["ACT_TEST_CHARACTER_PREVIEW_DIRECTORY"] else { return }
        let output = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let fixture = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let source = "INT. BACK ROOM - NIGHT\n\nAn orange flick cuts through the pure darkness. The flame burns between calloused fingers. The man holding the cigarette is ORLEANS, a man who would blend into the crowd on a normal Tuesday, but now it is clear that he is the boss."
        let document = FountainDocument()
        try document.read(from: Data(source.utf8), ofType: "dev.act.fountain")
        document.characterWorkspace.prepare(screenplayURL: fixture.appendingPathComponent("Preview.fountain"), source: source)
        #expect(document.characterWorkspace.mark(selection: (source as NSString).range(of: "ORLEANS")))
        let model = document.characterWorkspace
        model.library.characters[0].marks[0].traits = [.init(attribute: "hands", value: "calloused", evidence: "calloused fingers")]
        model.library.characters[0].marks[0].extractedParagraph = model.library.characters[0].marks[0].paragraph
        model.library.characters[0].prompt = model.library.characters[0].suggestedPrompt
        model.save()
        for (name, width, section, appearance) in [
            ("characters-light", 1280.0, WorkspaceSection.characters, NSAppearance.Name.aqua),
            ("characters-narrow-dark", 820.0, .characters, .darkAqua),
            ("editor-mark-light", 1000.0, .screenplay, .aqua),
            ("characters-layout-fixture-narrow", 820.0, .characters, .aqua)
        ] {
            if name == "characters-layout-fixture-narrow" {
                // Synthetic raster for layout only. Never presented as generated character art.
                let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 512, pixelsHigh: 256, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
                memset(try #require(bitmap.bitmapData), 210, bitmap.bytesPerRow * bitmap.pixelsHigh)
                let data = try #require(bitmap.representation(using: .png, properties: [:]))
                let images = try #require(model.directory).appendingPathComponent("images")
                try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
                try data.write(to: images.appendingPathComponent("layout-fixture.png"))
                let version = CharacterSheetVersion(imageFile: "images/layout-fixture.png", prompt: "Synthetic layout fixture", agent: "grok")
                model.library.characters[0].versions = [version]
                model.library.characters[0].activeVersionID = version.id
                var connection = ImageAgentConnection(agent: .grok, executable: URL(fileURLWithPath: "/usr/bin/true"))
                connection.generationVerified = true; connection.editingVerified = true
                model.connections = [connection]; model.selectedAgent = .grok
            }
            let view = NSHostingView(rootView: WorkspaceView(document: document, initialWorkspace: section))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: appearance); window.contentView = view
            view.layoutSubtreeIfNeeded(); TestEditorHost.pump()
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(name + ".png"))
            window.contentView = nil; window.close()
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ActCharacterAppTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
