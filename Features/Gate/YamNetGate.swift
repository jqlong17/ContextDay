import Foundation
import OnnxRuntimeBindings

/// YAMNet-ONNX ~5s window gate; dual-rail labels; Music > Speech when tied (Spec §1.4 / §3.1).
final class YamNetGate {
    struct LabelResult {
        var track: SegmentTrack
        var label: GateLabel
        var windowStartMs: Int64
        var windowEndMs: Int64
        var speechScore: Float
        var musicScore: Float
    }

    private var session: ORTSession?
    private var classNames: [String] = []
    private var speechIndices: [Int] = []
    private var musicIndices: [Int] = []
    private(set) var isModelLoaded = false

    /// Load ONNX + class map from Bundle `Models/YAMNet/`.
    func loadModelIfNeeded() throws {
        if isModelLoaded { return }
        guard let modelURL = ModelBundlePaths.yamnetONNX,
              let mapURL = ModelBundlePaths.yamnetClassMap,
              FileManager.default.fileExists(atPath: modelURL.path),
              FileManager.default.fileExists(atPath: mapURL.path) else {
            throw GateError.modelLoadFailed(
                "YAMNet not found under Bundle Models/YAMNet/. Run Scripts/fetch-models.sh"
            )
        }

        do {
            classNames = try Self.loadClassMap(mapURL)
            speechIndices = classNames.enumerated().compactMap { idx, name in
                Self.isSpeechClass(name) ? idx : nil
            }
            musicIndices = classNames.enumerated().compactMap { idx, name in
                Self.isMusicClass(name) ? idx : nil
            }

            let env = try ORTEnv(loggingLevel: .warning)
            let opts = try ORTSessionOptions()
            try opts.setIntraOpNumThreads(2)
            session = try ORTSession(env: env, modelPath: modelURL.path, sessionOptions: opts)
            isModelLoaded = true
            NSLog("ContextDay Gate: loaded YAMNet ONNX (\(classNames.count) classes)")
        } catch let error as GateError {
            throw error
        } catch {
            throw GateError.modelLoadFailed("ONNX Runtime failed: \(error.localizedDescription)")
        }
    }

    /// Classify a 16 kHz mono PCM window (Int16 LE). Spec ~5s windows.
    func classify(track: SegmentTrack, pcmWindow: Data, windowStartMs: Int64, windowEndMs: Int64) -> LabelResult {
        do {
            try loadModelIfNeeded()
        } catch {
            NSLog("ContextDay Gate: load failed — \(error.localizedDescription); labeling .other")
            return LabelResult(
                track: track, label: .other,
                windowStartMs: windowStartMs, windowEndMs: windowEndMs,
                speechScore: 0, musicScore: 0
            )
        }

        let samples = Self.int16LEToFloat(pcmWindow)
        guard !samples.isEmpty, let session else {
            return LabelResult(
                track: track, label: .other,
                windowStartMs: windowStartMs, windowEndMs: windowEndMs,
                speechScore: 0, musicScore: 0
            )
        }

        do {
            let (speech, music) = try runScores(session: session, samples: samples)
            let label = Self.decideLabel(speechScore: speech, musicScore: music)
            return LabelResult(
                track: track, label: label,
                windowStartMs: windowStartMs, windowEndMs: windowEndMs,
                speechScore: speech, musicScore: music
            )
        } catch {
            NSLog("ContextDay Gate: inference failed — \(error.localizedDescription)")
            return LabelResult(
                track: track, label: .other,
                windowStartMs: windowStartMs, windowEndMs: windowEndMs,
                speechScore: 0, musicScore: 0
            )
        }
    }

    // MARK: - Inference

    private func runScores(session: ORTSession, samples: [Float]) throws -> (Float, Float) {
        // YAMNet expects float32 waveform @ 16 kHz; outputs scores [frames, 521].
        let inputShape: [NSNumber] = [NSNumber(value: samples.count)]
        let inputData = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        let input = try ORTValue(
            tensorData: NSMutableData(data: inputData),
            elementType: .float,
            shape: inputShape
        )
        let outputs = try session.run(
            withInputs: ["waveform": input],
            outputNames: Set(["scores"]),
            runOptions: nil
        )
        guard let scoresValue = outputs["scores"] else {
            throw GateError.inferenceFailed("missing 'scores' output — check yamnet.onnx export I/O names")
        }
        let scoresData = try scoresValue.tensorData() as Data
        let count = scoresData.count / MemoryLayout<Float>.size
        var scores = [Float](repeating: 0, count: count)
        _ = scores.withUnsafeMutableBytes { scoresData.copyBytes(to: $0) }

        let numClasses = max(classNames.count, 521)
        let frames = max(1, count / numClasses)
        var speechMax: Float = 0
        var musicMax: Float = 0
        for f in 0..<frames {
            let base = f * numClasses
            for idx in speechIndices where idx < numClasses {
                speechMax = max(speechMax, scores[base + idx])
            }
            for idx in musicIndices where idx < numClasses {
                musicMax = max(musicMax, scores[base + idx])
            }
        }
        return (speechMax, musicMax)
    }

    /// Music preferred when tied / both high (Spec §1.4).
    static func decideLabel(speechScore: Float, musicScore: Float, threshold: Float = 0.15) -> GateLabel {
        let speechHit = speechScore >= threshold
        let musicHit = musicScore >= threshold
        if musicHit && speechHit {
            return musicScore >= speechScore ? .music : .speech
        }
        if musicHit { return .music }
        if speechHit { return .speech }
        return .other
    }

    private static func isSpeechClass(_ name: String) -> Bool {
        let n = name.lowercased()
        if n == "speech" { return true }
        if n.contains("speech") || n.contains("conversation") || n.contains("narration")
            || n.contains("monologue") || n.contains("babbling") || n.contains("whisper")
            || n.contains("shout") || n.contains("yell") {
            return true
        }
        return false
    }

    private static func isMusicClass(_ name: String) -> Bool {
        let n = name.lowercased()
        if n == "music" { return true }
        if n.contains("music") || n.contains("singing") || n.contains("guitar")
            || n.contains("piano") || n.contains("drum") || n.contains("orchestra")
            || n.contains("instrument") || n.contains("synth") || n.contains("bass") {
            return true
        }
        return false
    }

    private static func loadClassMap(_ url: URL) throws -> [String] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var names: [String] = []
        for (i, line) in text.split(whereSeparator: \.isNewline).enumerated() {
            if i == 0 && line.lowercased().contains("display_name") { continue }
            // CSV: index,mid,display_name (display_name may be quoted)
            guard let firstComma = line.firstIndex(of: ",") else { continue }
            let rest = line[line.index(after: firstComma)...]
            guard let secondComma = rest.firstIndex(of: ",") else { continue }
            var name = String(rest[rest.index(after: secondComma)...])
            if name.hasPrefix("\"") && name.hasSuffix("\"") {
                name = String(name.dropFirst().dropLast())
            }
            names.append(name)
        }
        return names
    }

    private static func int16LEToFloat(_ data: Data) -> [Float] {
        let count = data.count / 2
        var samples = [Float](repeating: 0, count: count)
        data.withUnsafeBytes { raw in
            let buf = raw.bindMemory(to: Int16.self)
            for i in 0..<count {
                samples[i] = Float(buf[i]) / 32768.0
            }
        }
        return samples
    }

    enum GateError: Error, LocalizedError {
        case modelLoadFailed(String)
        case inferenceFailed(String)

        var errorDescription: String? {
            switch self {
            case .modelLoadFailed(let d): return d
            case .inferenceFailed(let d): return d
            }
        }
    }
}
