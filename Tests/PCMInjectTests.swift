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
        XCTAssertGreaterThan(pipeline.debugMicFilledBytes(), 0)
        XCTAssertEqual(pipeline.debugSystemFilledBytes(), 0)

        // Dual-track: system inject must not clear mic.
        let micBefore = pipeline.debugMicFilledBytes()
        _ = try pipeline.injectPCM(track: .system, pcm16kMono: pcm, padSilenceMs: 0, autoArm: true)
        XCTAssertEqual(pipeline.debugMicFilledBytes(), micBefore)
        XCTAssertGreaterThan(pipeline.debugSystemFilledBytes(), 0)

        pipeline.stop()
    }

    func testSyntheticFixturePassesVADMinSpeech() {
        let vad = VoiceActivityDetector()
        let pcm = PCMInject.makeSyntheticSpeechFixture(speechSeconds: 4.0, silenceSeconds: 2.0)
        let utts = vad.segment(pcm: pcm, streamStartMs: 1_000_000, sampleRate: 16_000)
        XCTAssertFalse(utts.isEmpty, "synthetic fixture must produce ≥1 VAD utterance")
        let minSamples = 16_000 * vad.minSpeechMs / 1000
        XCTAssertGreaterThanOrEqual(utts[0].endSample - utts[0].startSample, minSamples)
    }

    func testAgentIOInjectWithoutPipelineIsUnavailable() {
        // Explicit nil pipeline — simulates App UI not registering CaptureInjectHost.
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

    func testProtocolDispatchInjectPcm() throws {
        let pipeline = CapturePipeline(pcmVariant: .b, store: store)
        CaptureInjectHost.register(pipeline)
        let service = AgentIOService(store: store)
        let pcm = PCMInject.makeSyntheticSpeechFixture(speechSeconds: 3.2, silenceSeconds: 0)
        let b64 = pcm.base64EncodedString()
        let data = try AgentIOProtocol.dispatch(
            tool: "inject_pcm",
            arguments: [
                "track": "mic",
                "pcm_base64": b64,
                "sample_rate": 16_000,
                "auto_arm": true,
                "pad_silence_ms": 500,
            ],
            service: service
        )
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(obj?["ok"] as? Bool, true)
        XCTAssertEqual(obj?["track"] as? String, "mic")
        XCTAssertNotNil(obj?["poll_hint"] as? String)
        // Privacy: response must not include transcript text.
        XCTAssertNil(obj?["text"])
        XCTAssertNil(obj?["transcript"])
        pipeline.stop()
    }

    /// When YAMNet + SenseVoice models are present, inject should eventually insert a segment.
    /// Cloud/Linux CI without models → XCTSkip (clear signal, not a red fail).
    func testInjectToSegmentIfModelsPresent() throws {
        let hasYam =
            ModelBundlePaths.yamnetONNX.map { FileManager.default.fileExists(atPath: $0.path) } == true
        let hasAsr =
            ModelBundlePaths.senseVoiceEncoder.map { FileManager.default.fileExists(atPath: $0.path) } == true
            && ModelBundlePaths.senseVoicePreprocessor.map { FileManager.default.fileExists(atPath: $0.path) } == true
            && ModelBundlePaths.senseVoiceVocab.map { FileManager.default.fileExists(atPath: $0.path) } == true
        guard hasYam, hasAsr else {
            throw XCTSkip("YAMNet/SenseVoice models missing — run Scripts/fetch-models.sh on Mac")
        }

        // Prove same VAD→ASR→SQLite path. Disable gate so synthetic fixture is not
        // rejected as YAMNet `other` (live Mac retest keeps gate on via pcm-inject-example).
        var cfg = AppConfigStore.load()
        let previousGate = cfg.gateEnabled
        cfg.gateEnabled = false
        AppConfigStore.save(cfg)
        defer {
            var restore = AppConfigStore.load()
            restore.gateEnabled = previousGate
            AppConfigStore.save(restore)
        }

        let pipeline = CapturePipeline(pcmVariant: .b, store: store)
        CaptureInjectHost.register(pipeline)
        let before = store.queryRecent(limit: 5, track: .mic).count

        let fixtureURL = Self.locateCheckedInFixture()
        let pcm: Data
        if let fixtureURL {
            pcm = try Data(contentsOf: fixtureURL)
        } else {
            pcm = PCMInject.makeSyntheticSpeechFixture()
        }
        _ = try pipeline.injectPCM(track: .mic, pcm16kMono: pcm, padSilenceMs: 0, autoArm: true)

        let deadline = Date().addingTimeInterval(45)
        var after = before
        while Date() < deadline {
            after = store.queryRecent(limit: 5, track: .mic).count
            if after > before { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        pipeline.stop()
        XCTAssertGreaterThan(after, before, "expected new mic segment after inject")
    }

    private static func locateCheckedInFixture() -> URL? {
        let candidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Tests/Fixtures/speech_16k_mono_s4.pcm"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("docs/fixtures/speech_16k_mono_s4.pcm"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
