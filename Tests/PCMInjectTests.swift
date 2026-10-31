import XCTest
@testable import ContextDay

/// Debug PCM inject: resolve/path allowlist, ring append, dual-rail isolation.
/// Full ASR segment assert XCTSkips when models are missing.
final class PCMInjectTests: XCTestCase {
    private var tempDir: URL!
    private var store: SegmentStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContextDayPCMInject-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        // Scratch under a fake records root so path allowlist accepts files we write.
        UserDefaults.standard.set(tempDir.path, forKey: AppPaths.recordsRootPathKey)
        try AppPaths.ensureDirectoryTree()
        store = try SegmentStore.openIsolated(
            databaseURL: tempDir.appendingPathComponent("db/contextday.sqlite")
        )
    }

    override func tearDownWithError() throws {
        store = nil
        UserDefaults.standard.removeObject(forKey: AppPaths.recordsRootPathKey)
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    func testResolveBase64AndDownsample48k() throws {
        // 9 Int16 samples @48k → 3 samples @16k
        var pcm48 = Data()
        for v: Int16 in [100, 200, 300, 400, 500, 600, 700, 800, 900] {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { pcm48.append(contentsOf: $0) }
        }
        let b64 = pcm48.base64EncodedString()
        let resolved = try PCMInject.resolve(pcmBase64: b64, path: nil, sampleRate: 48_000)
        XCTAssertEqual(resolved.data16kMono.count, 6) // 3 samples
        XCTAssertEqual(resolved.sourceSampleRate, 48_000)
        XCTAssertEqual(resolved.durationMs, 3 * 1000 / 16_000)
    }

    func testResolvePathUnderRecordsRoot() throws {
        let fixture = PCMInject.makeSyntheticSpeechFixture(speechSeconds: 3.2, silenceSeconds: 0)
        let file = AppPaths.scratchDirectory.appendingPathComponent("clip.pcm")
        try fixture.write(to: file)
        let resolved = try PCMInject.resolve(
            pcmBase64: nil,
            path: file.path,
            sampleRate: 16_000
        )
        XCTAssertEqual(resolved.data16kMono.count, fixture.count)
        XCTAssertTrue(resolved.source.hasPrefix("path:"))
    }

    func testRejectPathOutsideAllowlist() {
        XCTAssertThrowsError(
            try PCMInject.resolve(
                pcmBase64: nil,
                path: "/etc/hosts",
                sampleRate: 16_000
            )
        ) { err in
            guard let io = err as? AgentIOError, case .invalidArgument = io else {
                return XCTFail("expected invalid_argument, got \(err)")
            }
        }
    }

    func testRejectBothPathAndBase64() {
        XCTAssertThrowsError(
            try PCMInject.resolve(pcmBase64: "AAAA", path: "/tmp/x", sampleRate: 16_000)
        )
    }

    func testInjectAppendsMicWithoutTouchingSystemRail() throws {
        let pipeline = CapturePipeline(pcmVariant: .b, store: store)
        CaptureInjectHost.register(pipeline)
        let pcm = PCMInject.makeSyntheticSpeechFixture(speechSeconds: 3.5, silenceSeconds: 2.0)
        let accept = try pipeline.injectPCM(track: .mic, pcm16kMono: pcm, padSilenceMs: 0, autoArm: true)
        XCTAssertTrue(accept.pipelineRunning)
        XCTAssertTrue(accept.injectSession)
        XCTAssertEqual(accept.track, "mic")
        XCTAssertGreaterThan(accept.acceptedBytes, 0)
        XCTAssertGreaterThan(pipeline.debugMicFilledBytes(), 0)
        XCTAssertEqual(pipeline.debugSystemFilledBytes(), 0)

        // Dual-track: system inject must not clear mic.
        let micBefore = pipeline.debugMicFilledBytes()
        _ = try pipeline.injectPCM(track: .system, pcm16kMono: pcm, padSilenceMs: 0, autoArm: true)
        XCTAssertEqual(pipeline.debugMicFilledBytes(), micBefore)
        XCTAssertGreaterThan(pipeline.debugSystemFilledBytes(), 0)

        pipeline.stop()
    }

    func testEnergySyntheticPassesVADMinSpeech() {
        let vad = VoiceActivityDetector()
        let pcm = PCMInject.makeSyntheticSpeechFixture(speechSeconds: 4.0, silenceSeconds: 2.0)
        let utts = vad.segment(pcm: pcm, streamStartMs: 1_000_000, sampleRate: 16_000)
        XCTAssertFalse(utts.isEmpty, "energy synthetic must produce ≥1 VAD utterance")
        let minSamples = 16_000 * vad.minSpeechMs / 1000
        XCTAssertGreaterThanOrEqual(utts[0].endSample - utts[0].startSample, minSamples)
    }

    func testCheckedInChineseFixturePassesVAD() throws {
        guard let url = Self.locateCheckedInFixture() else {
            throw XCTSkip("checked-in speech_zh_16k_mono.pcm not found (cwd=\(FileManager.default.currentDirectoryPath))")
        }
        let pcm = try Data(contentsOf: url)
        XCTAssertGreaterThan(pcm.count, 16_000 * 2 * 3, "fixture should be >3s")
        let vad = VoiceActivityDetector()
        let utts = vad.segment(pcm: pcm, streamStartMs: 1_000_000, sampleRate: 16_000)
        XCTAssertFalse(utts.isEmpty, "Chinese speech fixture must clear VAD min speech")
    }

    func testAgentIOInjectWithoutPipelineIsUnavailable() {
        let service = AgentIOService(store: store)
        XCTAssertThrowsError(
            try service.injectPCM(
                trackRaw: "mic",
                pcmBase64: Data([0, 0, 1, 0]).base64EncodedString(),
                path: nil,
                sampleRate: 16_000,
                pipeline: nil
            )
        ) { err in
            guard let io = err as? AgentIOError, case .unavailable = io else {
                return XCTFail("expected unavailable")
            }
            XCTAssertEqual(io.payload["tool"], "inject_pcm")
        }
    }

    func testProtocolDispatchInjectPcmAccepted() throws {
        let pipeline = CapturePipeline(pcmVariant: .b, store: store)
        CaptureInjectHost.register(pipeline)
        let service = AgentIOService(store: store)
        let pcm: Data
        if let url = Self.locateCheckedInFixture() {
            pcm = try Data(contentsOf: url)
        } else {
            pcm = PCMInject.makeSyntheticSpeechFixture(speechSeconds: 3.2, silenceSeconds: 0)
        }
        let data = try AgentIOProtocol.dispatch(
            tool: "inject_pcm",
            arguments: [
                "track": "mic",
                "pcm_base64": pcm.base64EncodedString(),
                "sample_rate": 16_000,
                "auto_arm": true,
                "pad_silence_ms": 500,
            ],
            service: service
        )
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(obj?["ok"] as? Bool, true)
        XCTAssertEqual(obj?["track"] as? String, "mic")
        XCTAssertGreaterThan(obj?["accepted_bytes"] as? Int ?? 0, 0)
        XCTAssertNotNil(obj?["poll_hint"] as? String)
        // Privacy: response must not include transcript text.
        XCTAssertNil(obj?["text"])
        XCTAssertNil(obj?["transcript"])
        pipeline.stop()
    }

    /// Gate ON + models present → expect a mic segment with non-empty ASR text.
    /// Missing models → XCTSkip (CI without fetch-models).
    func testInjectToNonEmptySegmentIfModelsPresent() throws {
        let hasYam =
            ModelBundlePaths.yamnetONNX.map { FileManager.default.fileExists(atPath: $0.path) } == true
        let hasAsr =
            ModelBundlePaths.senseVoiceEncoder.map { FileManager.default.fileExists(atPath: $0.path) } == true
            && ModelBundlePaths.senseVoicePreprocessor.map { FileManager.default.fileExists(atPath: $0.path) } == true
            && ModelBundlePaths.senseVoiceVocab.map { FileManager.default.fileExists(atPath: $0.path) } == true
        guard hasYam, hasAsr else {
            throw XCTSkip("YAMNet/SenseVoice models missing — run Scripts/fetch-models.sh on Mac")
        }
        guard let fixtureURL = Self.locateCheckedInFixture() else {
            throw XCTSkip("speech_zh_16k_mono.pcm missing — run Scripts/generate-pcm-inject-fixture.sh")
        }

        // Keep gate ON: Chinese TTS fixture must get speech / send_asr (not music buzz).
        var cfg = AppConfigStore.load()
        let previousGate = cfg.gateEnabled
        cfg.gateEnabled = true
        AppConfigStore.save(cfg)
        defer {
            var restore = AppConfigStore.load()
            restore.gateEnabled = previousGate
            AppConfigStore.save(restore)
        }

        let pipeline = CapturePipeline(pcmVariant: .b, store: store)
        CaptureInjectHost.register(pipeline)
        let beforeIDs = Set(store.queryRecent(limit: 20, track: .mic).map(\.id))

        let pcm = try Data(contentsOf: fixtureURL)
        let accept = try pipeline.injectPCM(track: .mic, pcm16kMono: pcm, padSilenceMs: 0, autoArm: true)
        XCTAssertGreaterThan(accept.acceptedBytes, 0)
        XCTAssertTrue(accept.pipelineRunning)

        let deadline = Date().addingTimeInterval(60)
        var newest: Segment?
        while Date() < deadline {
            let rows = store.queryRecent(limit: 20, track: .mic)
            newest = rows.first { !beforeIDs.contains($0.id) }
            if let text = newest?.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                break
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        pipeline.stop()

        guard let seg = newest else {
            return XCTFail("expected new mic segment after inject (gate ON + Chinese fixture)")
        }
        let text = (seg.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(text.isEmpty, "ASR text must be non-empty (got gate/ASR empty)")
        // Soft content check — SenseVoice may paraphrase; require CJK presence.
        let hasCJK = text.unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF }
        XCTAssertTrue(hasCJK, "expected some Chinese characters in ASR text, got chars=\(text.count)")
    }

    private static func locateCheckedInFixture() -> URL? {
        let name = "speech_zh_16k_mono.pcm"
        let candidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Tests/Fixtures/\(name)"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("docs/fixtures/\(name)"),
            Bundle(for: PCMInjectTests.self).resourceURL?
                .appendingPathComponent("Fixtures/\(name)"),
        ].compactMap { $0 }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
