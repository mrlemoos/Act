import XCTest
@testable import ActCore

final class GenerationTests: XCTestCase {
    func testDecodedShotsHaveTrustedSceneIDsAndTrimmedFields() throws {
        let output = """
        llama.cpp banner
        {"shots":[{"framing":" Wide ","action":"A woman opens the door.","cameraMovement":"Static","rationale":"Establish the threshold."}]}
        """
        let shots = try LocalShotGenerator.decode(output: output, sceneID: "scene-one")
        XCTAssertEqual(shots.count, 1)
        XCTAssertEqual(shots[0].sceneID, "scene-one")
        XCTAssertEqual(shots[0].framing, "Wide")
    }

    func testRejectsTruncationMissingFieldsEmptyFieldsAndTooManyShots() {
        for value in ["{}", "{\"shots\":[]}", "{\"shots\":[{\"framing\":\"wide\"}]}", "{\"shots\":[", "{\"shots\":[{\"framing\":\" \",\"action\":\"a\",\"cameraMovement\":\"b\",\"rationale\":\"c\"}]}"] {
            XCTAssertThrowsError(try LocalShotGenerator.decode(output: value, sceneID: "1"))
        }
        let shot = "{\"framing\":\"wide\",\"action\":\"a\",\"cameraMovement\":\"static\",\"rationale\":\"c\"}"
        XCTAssertThrowsError(try LocalShotGenerator.decode(output: "{\"shots\":[\(shot),\(shot)]}", sceneID: "1", maximumShots: 1))
    }

    func testUnavailableRuntimeAndOversizedSceneAreActionable() async throws {
        let configuration = LocalGenerationConfiguration(executableURL: URL(fileURLWithPath: "/missing/llama-cli"), modelURL: URL(fileURLWithPath: "/missing/model.gguf"))
        do {
            _ = try await LocalShotGenerator().generate(sceneID: "1", heading: "INT. HOME", source: "Action.", configuration: configuration)
            XCTFail("Should reject missing executable")
        } catch { XCTAssertEqual(error as? GenerationError, .runtimeMissing) }
        do {
            _ = try await LocalShotGenerator().generate(sceneID: "1", heading: "INT. HOME", source: String(repeating: "é", count: 6_001), configuration: configuration)
            XCTFail("Should reject scene beyond byte budget")
        } catch { XCTAssertEqual(error as? GenerationError, .sceneTooLong) }
    }

    func testProcessAdapterRunsOfflineAndDoesNotMutateSource() async throws {
        let fixture = try makeRuntime(script: """
        #!/bin/sh
        case " $* " in *" --offline "*) ;; *) exit 10 ;; esac
        printf '%s' '{"shots":[{"framing":"Wide","action":"The door opens.","cameraMovement":"Static","rationale":"Establish location."}]}'
        """)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let source = "INT. HOME - DAY\n\nThe door opens."
        let shots = try await LocalShotGenerator().generate(sceneID: "one", heading: "INT. HOME - DAY", source: source, configuration: fixture.configuration)
        XCTAssertEqual(shots.first?.action, "The door opens.")
        XCTAssertEqual(source, "INT. HOME - DAY\n\nThe door opens.")
    }

    func testCancellationTerminatesGeneration() async throws {
        let fixture = try makeRuntime(script: "#!/bin/sh\n: > \"$0.started\"\nexec /bin/sleep 30\n")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let generation = Task {
            try await LocalShotGenerator().generate(sceneID: "one", heading: "INT. HOME", source: "Door.", configuration: fixture.configuration)
        }
        let started = URL(fileURLWithPath: fixture.configuration.executableURL.path + ".started")
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !FileManager.default.fileExists(atPath: started.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        guard FileManager.default.fileExists(atPath: started.path) else {
            generation.cancel()
            _ = try? await generation.value
            return XCTFail("The fixture runtime never started")
        }
        let cancelledAt = ContinuousClock.now
        generation.cancel()
        do {
            _ = try await generation.value
            XCTFail("Cancellation should fail generation")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(cancelledAt.duration(to: .now), .seconds(5), "Cancellation must stop the running process promptly")
    }

    func testRealOfflineInferenceWhenExplicitlyConfigured() async throws {
        guard let path = ProcessInfo.processInfo.environment["ACT_TEST_MODEL"],
              let executable = LocalGenerationConfiguration.discoveredExecutableURL else {
            throw XCTSkip("Set ACT_TEST_MODEL to an existing GGUF for real Metal inference.")
        }
        let shots = try await LocalShotGenerator().generate(sceneID: "live-scene", heading: "INT. KITCHEN - DAWN", source: "INT. KITCHEN - DAWN\n\nMara sets a sealed letter on the table. She watches the door. Someone knocks. She hides the letter beneath a cup.", configuration: .init(executableURL: executable, modelURL: URL(fileURLWithPath: path), maximumShots: 4))
        XCTAssertFalse(shots.isEmpty)
        XCTAssertTrue(shots.allSatisfy { $0.sceneID == "live-scene" })
        print("REAL OFFLINE SHOTS: \(shots)")
    }

    func testRecommendedModelDownloadAndOfflineInferenceWhenExplicitlyConfigured() async throws {
        guard let path = ProcessInfo.processInfo.environment["ACT_TEST_DOWNLOAD_DIRECTORY"],
              let executable = LocalGenerationConfiguration.discoveredExecutableURL else {
            throw XCTSkip("Set ACT_TEST_DOWNLOAD_DIRECTORY to validate the 4.68 GB recommended-model download and real inference.")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: directory.path)
        let available = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        let store = LocalModelStore(directory: directory)
        guard store.isDownloaded || available >= LocalModelStore.recommendedSizeBytes * 2 else {
            throw XCTSkip("Recommended-model verification needs at least 9.37 GB of free working space.")
        }
        print("RECOMMENDED DOWNLOAD START: \(directory.path), free bytes \(available)")
        let modelURL = try await store.download()
        XCTAssertTrue(store.isDownloaded)
        XCTAssertEqual(modelURL, store.modelURL)
        print("RECOMMENDED DOWNLOAD VERIFIED: \(LocalModelStore.recommendedSizeBytes) bytes, both pinned SHA256 checks passed")
        let source = """
        INT. KITCHEN - DAWN

        Mara sets a sealed letter on the table. She smooths its creased envelope with her thumb.

        Three sharp knocks at the front door. Mara freezes. She slides the letter beneath a cup.

        MARA
        Who is it?

        No answer. The door handle turns.
        """
        let shots = try await LocalShotGenerator().generate(sceneID: "recommended-model-scene", heading: "INT. KITCHEN - DAWN", source: source, configuration: .init(executableURL: executable, modelURL: modelURL, maximumShots: 4))
        XCTAssertTrue((1...4).contains(shots.count), "The response must respect the requested shot limit")
        XCTAssertTrue(shots.allSatisfy { $0.sceneID == "recommended-model-scene" })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print("RECOMMENDED OFFLINE SHOTS: \(String(decoding: try encoder.encode(shots), as: UTF8.self))")
    }

    func testSnakeCaseFieldsAreTrustedAndFieldLengthBoundaryIsEnforced() throws {
        func output(action: String) throws -> String {
            let value: [String: Any] = ["shots": [["framing": " Close-up ", "action": action, "camera_movement": " Static ", "rationale": " Hold the silence. ", "sceneID": "untrusted-model-scene"]]]
            return String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
        }
        let accepted = try LocalShotGenerator.decode(output: output(action: String(repeating: "é", count: 2_000)), sceneID: "trusted-scene")
        XCTAssertEqual(accepted.first?.sceneID, "trusted-scene")
        XCTAssertEqual(accepted.first?.cameraMovement, "Static")
        XCTAssertEqual(accepted.first?.rationale, "Hold the silence.")
        XCTAssertThrowsError(try LocalShotGenerator.decode(output: output(action: String(repeating: "é", count: 2_001)), sceneID: "trusted-scene"))
        XCTAssertThrowsError(try LocalShotGenerator.decode(output: String(repeating: "x", count: 1_048_577), sceneID: "trusted-scene"))
    }

    func testEmptySceneMissingModelAndInvalidModelReturnSpecificFailures() async throws {
        let fixture = try makeRuntime(script: "#!/bin/sh\nexit 0\n")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        do {
            _ = try await LocalShotGenerator().generate(sceneID: "one", heading: "INT. HOME", source: " \r\n\t", configuration: fixture.configuration)
            XCTFail("Whitespace-only source should fail before process launch")
        } catch { XCTAssertEqual(error as? GenerationError, .emptyScene) }
        try FileManager.default.removeItem(at: fixture.configuration.modelURL)
        do {
            _ = try await LocalShotGenerator().generate(sceneID: "one", heading: "INT. HOME", source: "Action.", configuration: fixture.configuration)
            XCTFail("Missing model should be reported")
        } catch { XCTAssertEqual(error as? GenerationError, .modelMissing) }
        try Data("not a GGUF".utf8).write(to: fixture.configuration.modelURL)
        do {
            _ = try await LocalShotGenerator().generate(sceneID: "one", heading: "INT. HOME", source: "Action.", configuration: fixture.configuration)
            XCTFail("Invalid model header should be reported")
        } catch { XCTAssertEqual(error as? GenerationError, .invalidModel) }
    }

    func testFailedRuntimePreservesDiagnosticAndMalformedSuccessIsRejected() async throws {
        let failed = try makeRuntime(script: "#!/bin/sh\nprintf '%s' 'Metal allocation failed' >&2\nexit 7\n")
        defer { try? FileManager.default.removeItem(at: failed.directory) }
        do {
            _ = try await LocalShotGenerator().generate(sceneID: "one", heading: "INT. HOME", source: "Action.", configuration: failed.configuration)
            XCTFail("Nonzero runtime exit must fail")
        } catch {
            guard let generationError = error as? GenerationError, case .runtimeFailed(let reason) = generationError else { return XCTFail("Expected runtimeFailed, got \(error)") }
            XCTAssertTrue(reason.contains("Metal allocation failed"))
        }
        let malformed = try makeRuntime(script: "#!/bin/sh\nprintf '%s' 'successful process, invalid shot output'\n")
        defer { try? FileManager.default.removeItem(at: malformed.directory) }
        do {
            _ = try await LocalShotGenerator().generate(sceneID: "one", heading: "INT. HOME", source: "Action.", configuration: malformed.configuration)
            XCTFail("Successful exit alone must not count as valid generation")
        } catch { XCTAssertEqual(error as? GenerationError, .invalidOutput) }
    }

    private func makeRuntime(script: String) throws -> (directory: URL, configuration: LocalGenerationConfiguration) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ActGenerationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("llama-cli")
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let model = directory.appendingPathComponent("model.gguf")
        try Data("GGUFfixture".utf8).write(to: model)
        return (directory, .init(executableURL: executable, modelURL: model))
    }
}
