import XCTest
import AppKit
@testable import ActCore

final class CharacterSheetTests: XCTestCase {
    let action = "An orange flick cuts through the pure darkness. The flame burns between calloused fingers.\r\nThe man holding the cigarette is ORLEANS, a man who would blend into the crowd on a normal Tuesday, but now it is clear that he is the boss."

    func testManualSelectionCapturesOnlyContainingActionParagraphWithoutChangingFountain() throws {
        let source = "INT. CAFÉ - NIGHT\r\n\r\n\(action)\r\n\r\nAnother paragraph.\r\n\r\nORLEANS\r\nLeave."
        let selected = (source as NSString).range(of: "ORLEANS")
        let block = try CharacterActionBlock.selected(in: source, range: selected)
        XCTAssertEqual(block.name, "ORLEANS")
        XCTAssertEqual(block.text, action.replacingOccurrences(of: "\r\n", with: "\n"))
        var library = CharacterLibrary()
        try library.mark(source: source, selection: selected)
        XCTAssertEqual(library.characters.count, 1)
        XCTAssertEqual(library.characters[0].marks[0].nameRange, selected)
        XCTAssertTrue(source.contains("\r\n"))
        XCTAssertEqual(source, "INT. CAFÉ - NIGHT\r\n\r\n\(action)\r\n\r\nAnother paragraph.\r\n\r\nORLEANS\r\nLeave.")
    }

    func testRejectsDialogueHeadingsCommentsEmptyAndMixedSelections() throws {
        let source = "INT. ROOM - DAY\n\nA man is ORLEANS. [[SECRET]]\n\nORLEANS\nGo away."
        for selection in [NSRange(location: 0, length: 0), (source as NSString).range(of: "INT. ROOM"),
                          (source as NSString).range(of: "Go away"), (source as NSString).range(of: "SECRET"),
                          NSRange(location: 0, length: (source as NSString).length), NSRange(location: Int.max, length: 4)] {
            XCTAssertThrowsError(try CharacterActionBlock.selected(in: source, range: selection))
        }
        XCTAssertThrowsError(try CharacterActionBlock.selected(in: source, range: (source as NSString).range(of: "ORLEANS", options: .backwards)))
    }

    func testLinkedOccurrencesKeepIdentityColourAndFlagConflictingEvidence() throws {
        let source = "ORLEANS has black hair.\n\nORLEANS has grey hair."
        var library = CharacterLibrary()
        let id = try library.mark(source: source, selection: (source as NSString).range(of: "ORLEANS"))
        try library.mark(source: source, selection: (source as NSString).range(of: "ORLEANS", options: .backwards), characterID: id)
        library.characters[0].marks[0].traits = [.init(attribute: "hair", value: "black", evidence: "black hair")]
        library.characters[0].marks[1].traits = [.init(attribute: "hair", value: "grey", evidence: "grey hair")]
        XCTAssertEqual(library.characters.count, 1)
        XCTAssertEqual(library.characters[0].marks.count, 2)
        XCTAssertEqual(library.characters[0].contradictions, ["hair: black / grey"])
        let before = library
        XCTAssertThrowsError(try library.mark(source: source, selection: (source as NSString).range(of: "ORLEANS")))
        XCTAssertEqual(before, library, "Rejected duplicate must not create an empty character")
    }

    func testVisibleNameAfterClosedCommentCanBeMarkedButHiddenNamesCannot() throws {
        let source = "A man [[ORLEANS is a secret alias]] walks. ORLEANS has calloused hands."
        XCTAssertThrowsError(try CharacterActionBlock.selected(in: source, range: (source as NSString).range(of: "ORLEANS")))
        let block = try CharacterActionBlock.selected(in: source, range: (source as NSString).range(of: "ORLEANS", options: .backwards))
        XCTAssertFalse(block.text.contains("secret alias"))
        XCTAssertTrue(block.text.contains("ORLEANS has calloused hands"))
    }

    func testRebaseUnicodeEditsFlagParagraphChangesWithoutOverwritingPrompt() throws {
        let source = "ORLEANS has calloused hands."
        var library = CharacterLibrary()
        try library.mark(source: source, selection: (source as NSString).range(of: "ORLEANS"))
        library.characters[0].marks[0].extractedParagraph = source
        library.characters[0].prompt = "My independent appearance direction."
        let moved = "Éva 👁 waits.\n\n" + source
        library.reconcile(from: source, to: moved)
        XCTAssertEqual(library.characters[0].marks[0].nameRange, (moved as NSString).range(of: "ORLEANS"))
        XCTAssertFalse(library.characters[0].needsReview)
        let edited = moved.replacingOccurrences(of: "calloused", with: "scarred")
        library.reconcile(from: moved, to: edited)
        XCTAssertTrue(library.characters[0].needsReview)
        XCTAssertEqual(library.characters[0].prompt, "My independent appearance direction.")
        let renamed = edited.replacingOccurrences(of: "ORLEANS", with: "MARA")
        library.reconcile(from: edited, to: renamed)
        XCTAssertTrue(library.characters[0].marks[0].isDetached)
    }

    func testReopeningChangedSourceNeverTrustsCoincidingNameOffsets() throws {
        let source = "ORLEANS has calloused hands."
        var library = CharacterLibrary()
        try library.mark(source: source, selection: (source as NSString).range(of: "ORLEANS"))
        var reopened = try CharacterLibraryStore.decode(CharacterLibraryStore.data(library))
        reopened.verify(source: "ORLEANS has scarred hands.")
        XCTAssertTrue(reopened.characters[0].marks[0].isDetached)
    }

    func testMLXEvidenceMustComeFromParagraphAndMustBePhysical() throws {
        let valid = #"{"traits":[{"attribute":"hands","value":"calloused","evidence":"calloused fingers"}]}"#
        let traits = try CharacterPhysicalExtractor.decode(valid, paragraph: action)
        XCTAssertEqual(traits, [.init(attribute: "hands", value: "calloused", evidence: "calloused fingers")])
        XCTAssertEqual(try CharacterPhysicalExtractor.decode(#"{"traits":[]}"#, paragraph: action), [])
        for invalid in [valid.replacingOccurrences(of: "calloused fingers", with: "blue eyes"),
                        valid.replacingOccurrences(of: "hands", with: "occupation"), "{}", "{\"traits\":["] {
            XCTAssertThrowsError(try CharacterPhysicalExtractor.decode(invalid, paragraph: action))
        }
    }

    func testPortableLibraryRejectsTraversalUnsupportedVersionsAndBrokenActiveReferences() throws {
        var library = CharacterLibrary()
        try library.mark(source: action, selection: (action as NSString).range(of: "ORLEANS"))
        library.characters[0].versions = [.init(imageFile: "images/one.png", prompt: "Prompt", agent: "grok")]
        library.characters[0].activeVersionID = library.characters[0].versions[0].id
        XCTAssertEqual(try CharacterLibraryStore.decode(CharacterLibraryStore.data(library)), library)
        for path in ["../image.png", "/tmp/image.png", "images/../../file.png", "images/x.svg", "images/../x.png", "images\\x.png"] {
            library.characters[0].versions[0].imageFile = path
            XCTAssertThrowsError(try CharacterLibraryStore.data(library))
        }
        library.characters[0].versions[0].imageFile = "images/one.png"
        library.characters[0].activeVersionID = UUID()
        XCTAssertThrowsError(try CharacterLibraryStore.data(library))
        library.characters[0].activeVersionID = nil
        library.version = 99
        XCTAssertThrowsError(try CharacterLibraryStore.data(library))
    }

    func testAgentCommandsNeverUseGenericCursorAliasOrUnrestrictedGrokTools() {
        XCTAssertEqual(CharacterImageAgent.cursor.executableName, "cursor-agent")
        let directory = URL(fileURLWithPath: "/tmp/Act space")
        let args = CharacterImageAgent.grok.arguments(prompt: "literal $(payload)", directory: directory, reference: nil)
        XCTAssertEqual(args[args.firstIndex(of: "--tools")! + 1], "image_gen")
        XCTAssertTrue(args.contains("MCPTool(*)"))
        XCTAssertTrue(args.contains("--no-subagents"))
        let edit = CharacterImageAgent.grok.arguments(prompt: "edit", directory: directory, reference: directory.appendingPathComponent("reference.png"))
        XCTAssertEqual(edit[edit.firstIndex(of: "--tools")! + 1], "image_edit")
    }

    func testAgentOutputParsesNestedJSONAndRejectsInvalidImages() throws {
        let output = #"{"result":"{\"image_path\":\"/tmp/a.png\"}"}"#
        XCTAssertEqual(CharacterImageGenerator.reportedPaths(output), ["/tmp/a.png"])
        XCTAssertThrowsError(try CharacterImageGenerator.validate(Data("<svg></svg>".utf8)))
        XCTAssertThrowsError(try CharacterImageGenerator.validate(Data("not an image".utf8)))
        let image = try png()
        XCTAssertEqual(try CharacterImageGenerator.validate(image).fileExtension, "png")
    }

    func testImageSubprocessImportsOnlyNewValidRasterAndKeepsPromptLiteral() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pngFile = directory.appendingPathComponent("fixture.png")
        try png().write(to: pngFile)
        let script = """
        #!/bin/sh
        /bin/cat > received.txt
        /usr/bin/grep -F 'literal $(do-not-run)' received.txt >/dev/null || exit 9
        /bin/cp '\(pngFile.path)' result.png
        printf '%s' '{"image_path":"result.png"}'
        """
        let executable = try runtime(script, directory: directory)
        let image = try await CharacterImageGenerator.generate(agent: .codex, executable: executable, prompt: "literal $(do-not-run)")
        XCTAssertEqual(image.data, try Data(contentsOf: pngFile))
    }

    func testMLXCommandUsesOfflineFlagsAndActualStdinParagraph() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("{}".utf8).write(to: directory.appendingPathComponent("config.json"))
        try Data().write(to: directory.appendingPathComponent("model.safetensors"))
        let executable = try runtime("""
        #!/bin/sh
        test "$HF_HUB_OFFLINE" = 1 || exit 4
        test "$TRANSFORMERS_OFFLINE" = 1 || exit 5
        /bin/cat > received.txt
        /usr/bin/grep -F 'calloused fingers' received.txt >/dev/null || exit 6
        printf '%s' '{"traits":[{"attribute":"hands","value":"calloused","evidence":"calloused fingers"}]}'
        """, directory: directory)
        let details = try await CharacterPhysicalExtractor.extract(name: "ORLEANS", paragraph: action, configuration: .init(executable: executable, modelDirectory: directory))
        XCTAssertEqual(details.first?.value, "calloused")
    }

    func testCancellationKillsBackgroundProcessGroup() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = try runtime("""
        #!/bin/sh
        /bin/sleep 60 &
        echo $! > child.pid
        wait
        """, directory: directory)
        let job = Task { try await BackgroundCommand().run(executable: executable, arguments: [], directory: directory) }
        let childFile = directory.appendingPathComponent("child.pid")
        for _ in 0..<200 {
            if FileManager.default.fileExists(atPath: childFile.path) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let child = try XCTUnwrap(Int32(String(contentsOf: childFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        job.cancel()
        do { _ = try await job.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        // The descendant must not remain executable after cancellation. A brief zombie can await launchd reaping.
        for _ in 0..<100 {
            if kill(child, 0) != 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotEqual(kill(child, 0), 0)
    }

    func testRealMLXExtractionWhenExplicitlyConfigured() async throws {
        guard let executable = ProcessInfo.processInfo.environment["ACT_TEST_MLX_RUNTIME"],
              let model = ProcessInfo.processInfo.environment["ACT_TEST_MLX_MODEL"] else { throw XCTSkip("Set ACT_TEST_MLX_RUNTIME and ACT_TEST_MLX_MODEL for actual local extraction.") }
        let details = try await CharacterPhysicalExtractor.extract(name: "ORLEANS", paragraph: action, configuration: .init(executable: URL(fileURLWithPath: executable), modelDirectory: URL(fileURLWithPath: model)))
        XCTAssertTrue(details.contains { $0.value.localizedCaseInsensitiveContains("calloused") })
        XCTAssertFalse(details.contains { $0.attribute == "occupation" })
        print("REAL MLX PHYSICAL DETAILS: \(details)")
    }

    private func png() throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 96, pixelsHigh: 96, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ActCharacterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func runtime(_ script: String, directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("runtime")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
