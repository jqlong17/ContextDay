import Foundation

/// Offline-friendly smoke / triage report (Agent IO `self_check`, unit-testable).
enum SelfCheck {
    struct ModelPresence: Codable, Equatable, Sendable {
        var senseVoiceEncoder: Bool
        var senseVoicePreprocessor: Bool
        var senseVoiceVocab: Bool
        var yamnetOnnx: Bool
        var yamnetClassMap: Bool

        var allSenseVoicePresent: Bool {
            senseVoiceEncoder && senseVoicePreprocessor && senseVoiceVocab
        }

        var allYamnetPresent: Bool {
            yamnetOnnx && yamnetClassMap
        }

        enum CodingKeys: String, CodingKey {
            case senseVoiceEncoder = "sensevoice_encoder"
            case senseVoicePreprocessor = "sensevoice_preprocessor"
            case senseVoiceVocab = "sensevoice_vocab"
            case yamnetOnnx = "yamnet_onnx"
            case yamnetClassMap = "yamnet_class_map"
        }
    }

    struct DatabaseStatus: Codable, Equatable, Sendable {
        var openable: Bool
        var path: String
        var detail: String?

        enum CodingKeys: String, CodingKey {
            case openable, path, detail
        }
    }

    struct AgentIOStatus: Codable, Equatable, Sendable {
        var listening: Bool
        var port: Int

        enum CodingKeys: String, CodingKey {
            case listening, port
        }
    }

    struct Report: Codable, Equatable, Sendable {
        var ok: Bool
        var service: String
        var checkedAtMs: Int64
        var recordsRoot: String
        var permissions: PermissionSnapshot
        var runtime: RuntimeHealthDTO
        var database: DatabaseStatus
        var models: ModelPresence
        var agentIO: AgentIOStatus
        var notes: [String]

        enum CodingKeys: String, CodingKey {
            case ok, service
            case checkedAtMs = "checked_at_ms"
            case recordsRoot = "records_root"
            case permissions, runtime, database, models
            case agentIO = "agent_io"
            case notes
        }
    }

    /// Build a full snapshot. Safe to call without UI / without starting capture.
    static func run(
        store: SegmentStore = .shared,
        health: RuntimeHealth = .shared,
        agentListening: Bool = AgentIOHTTPServer.shared.isListening,
        agentPort: UInt16 = AgentIOHTTPServer.shared.port
    ) -> Report {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let perms = PermissionStatus.snapshot()
        let runtime = health.snapshot()
        let db = probeDatabase(store: store)
        let models = probeModels()
        let agent = AgentIOStatus(listening: agentListening, port: Int(agentPort))

        var notes: [String] = []
        if let mic = perms.entry(.microphone), mic.state == .denied || mic.state == .restricted {
            notes.append("microphone not usable: \(mic.state.rawValue)")
        }
        if runtime.recordingDesync {
            notes.append("recording UI vs pipeline desync")
        }
        if let err = runtime.lastCaptureError {
            notes.append("last_capture_error present (\(err.count) chars)")
        }
        if !db.openable {
            notes.append("database not openable")
        }
        if !models.allSenseVoicePresent {
            notes.append("SenseVoice Core ML artifacts missing — run Scripts/fetch-models.sh")
        }
        if AppConfigStore.load().gateEnabled && !models.allYamnetPresent {
            notes.append("YAMNet missing while gate_enabled — run Scripts/fetch-models.sh")
        }
        if !agent.listening {
            notes.append("Agent IO HTTP not listening")
        }

        let ok = db.openable && !runtime.recordingDesync && agent.listening
        return Report(
            ok: ok,
            service: "ContextDay",
            checkedAtMs: now,
            recordsRoot: AppPaths.recordsRoot.path,
            permissions: perms,
            runtime: runtime,
            database: db,
            models: models,
            agentIO: agent,
            notes: notes
        )
    }

    static func probeModels() -> ModelPresence {
        let fm = FileManager.default
        func exists(_ url: URL?) -> Bool {
            guard let url else { return false }
            return fm.fileExists(atPath: url.path)
        }
        return ModelPresence(
            senseVoiceEncoder: exists(ModelBundlePaths.senseVoiceEncoder),
            senseVoicePreprocessor: exists(ModelBundlePaths.senseVoicePreprocessor),
            senseVoiceVocab: exists(ModelBundlePaths.senseVoiceVocab),
            yamnetOnnx: exists(ModelBundlePaths.yamnetONNX),
            yamnetClassMap: exists(ModelBundlePaths.yamnetClassMap)
        )
    }

    private static func probeDatabase(store: SegmentStore) -> DatabaseStatus {
        let path = AppPaths.databaseFile.path
        if store.isOpen {
            // Lightweight round-trip: empty query must not throw / crash.
            _ = store.queryRecent(limit: 1, track: nil)
            return DatabaseStatus(openable: true, path: path, detail: "open")
        }
        // Shared store not open yet — try an isolated open of the same path.
        do {
            let probe = try SegmentStore.openIsolated(databaseURL: AppPaths.databaseFile)
            _ = probe.queryRecent(limit: 1, track: nil)
            return DatabaseStatus(openable: true, path: path, detail: "opened_for_probe")
        } catch {
            return DatabaseStatus(
                openable: false,
                path: path,
                detail: error.localizedDescription
            )
        }
    }
}
