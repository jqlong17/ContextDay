import CoreML
import Darwin
import Foundation

/// SenseVoice Core ML int8 — primary ASR path (Spec §1.4 / §3.1 / §3.5).
/// Never falls back to SenseVoice ONNX; load failure surfaces as `modelLoadFailed`.
final class SenseVoiceASR {
    struct Transcript {
        var text: String
        var modelId: String
        var modelVersion: String?
    }

    private(set) var isModelLoaded = false

    private var preprocessor: MLModel?
    private var encoder: MLModel?
    private var vocabulary: [String] = []

    private let featureDim = 560
    private let buckets = [128, 256, 512, 1024, 1800]
    private let blankId = 0
    private let language: Int32 = 0 // auto
    private let textNorm: Int32 = 15 // woitn
    private let waveformScale: Float = 32_768
    private let modelId = "sensevoice-coreml-int8"

    func loadModelIfNeeded() throws {
        if isModelLoaded { return }

        guard let encURL = ModelBundlePaths.senseVoiceEncoder,
              let prepURL = ModelBundlePaths.senseVoicePreprocessor,
              let vocabURL = ModelBundlePaths.senseVoiceVocab else {
            throw ASRError.modelLoadFailed(
                "SenseVoice Core ML int8 not found under Bundle Models/SenseVoiceSmall_int8/. Run Scripts/fetch-models.sh or copy models locally."
            )
        }
        guard FileManager.default.fileExists(atPath: encURL.path),
              FileManager.default.fileExists(atPath: prepURL.path),
              FileManager.default.fileExists(atPath: vocabURL.path) else {
            throw ASRError.modelLoadFailed(
                "Missing SenseVoice artifacts at \(encURL.path) / \(prepURL.path) / \(vocabURL.path)"
            )
        }

        do {
            let prepConfig = MLModelConfiguration()
            prepConfig.computeUnits = .cpuOnly
            preprocessor = try MLModel(contentsOf: prepURL, configuration: prepConfig)

            let encConfig = MLModelConfiguration()
            // Prefer CPU: .cpuAndNeuralEngine can hang on ANE compile on some Macs.
            // Still Core ML int8 (Spec forbids SenseVoice ONNX fallback).
            encConfig.computeUnits = .cpuOnly
            encoder = try MLModel(contentsOf: encURL, configuration: encConfig)

            let data = try Data(contentsOf: vocabURL)
            let decoded = try JSONDecoder().decode([String].self, from: data)
            guard decoded.count > 1 else {
                throw ASRError.modelLoadFailed("vocab.json has unexpected shape")
            }
            vocabulary = decoded
            isModelLoaded = true
            AppLog.info(.asr, "loaded SenseVoice Core ML int8 tokens=\(vocabulary.count)")
        } catch let error as ASRError {
            isModelLoaded = false
            throw error
        } catch {
            isModelLoaded = false
            throw ASRError.modelLoadFailed("Core ML load failed: \(error.localizedDescription)")
        }
    }

    /// Transcribe 16 kHz mono PCM (Int16 little-endian bytes or Float32 samples in Data as Int16).
    func transcribe(pcm16kMono: Data) throws -> Transcript {
        try loadModelIfNeeded()
        let samples = Self.int16LEToFloat(pcm16kMono)
        guard samples.count >= 1600 else { // ~0.1s
            return Transcript(text: "", modelId: modelId, modelVersion: nil)
        }
        let text = try runPipeline(samples: samples)
        return Transcript(text: text, modelId: modelId, modelVersion: "FluidInference/sensevoice-small-coreml")
    }

    func transcribe(samples16kMono: [Float]) throws -> Transcript {
        try loadModelIfNeeded()
        guard samples16kMono.count >= 1600 else {
            return Transcript(text: "", modelId: modelId, modelVersion: nil)
        }
        let text = try runPipeline(samples: samples16kMono)
        return Transcript(text: text, modelId: modelId, modelVersion: "FluidInference/sensevoice-small-coreml")
    }

    // MARK: - Pipeline

    private func runPipeline(samples: [Float]) throws -> String {
        guard let preprocessor, let encoder else {
            throw ASRError.modelLoadFailed("SenseVoice models not loaded")
        }

        let features = try runPreprocessor(preprocessor, audio: samples)
        let (logits, validFrames) = try runEncoder(encoder, features: features)
        return decode(logits: logits, validFrames: validFrames)
    }

    private func runPreprocessor(_ model: MLModel, audio: [Float]) throws -> MLMultiArray {
        let n = audio.count
        let waveform = try MLMultiArray(shape: [1, NSNumber(value: n)], dataType: .float32)
        let ptr = waveform.dataPointer.assumingMemoryBound(to: Float.self)
        for i in 0..<n {
            ptr[i] = audio[i] * waveformScale
        }
        let input = try MLDictionaryFeatureProvider(dictionary: ["waveform": MLFeatureValue(multiArray: waveform)])
        let out = try model.prediction(from: input)
        guard let features = out.featureValue(for: "features")?.multiArrayValue else {
            throw ASRError.inferenceFailed("preprocessor missing 'features' output")
        }
        return features
    }

    private func runEncoder(_ model: MLModel, features: MLMultiArray) throws -> (MLMultiArray, Int) {
        var t = features.shape[1].intValue
        let maxFrames = buckets.last ?? 1800
        if t > maxFrames { t = maxFrames }
        let bucket = pickBucket(forFrames: t)

        let speech = try MLMultiArray(
            shape: [1, NSNumber(value: bucket), NSNumber(value: featureDim)],
            dataType: .float32
        )
        let sptr = speech.dataPointer.assumingMemoryBound(to: Float.self)
        memset(sptr, 0, bucket * featureDim * MemoryLayout<Float>.size)
        let count = t * featureDim
        if features.dataType == .float32 {
            memcpy(sptr, features.dataPointer, count * MemoryLayout<Float>.size)
        } else {
            for i in 0..<count {
                sptr[i] = features[i].floatValue
            }
        }

        let lengths = try MLMultiArray(shape: [1], dataType: .int32)
        lengths[0] = NSNumber(value: Int32(t))
        let languageArr = try MLMultiArray(shape: [1], dataType: .int32)
        languageArr[0] = NSNumber(value: language)
        let textNormArr = try MLMultiArray(shape: [1], dataType: .int32)
        textNormArr[0] = NSNumber(value: textNorm)

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "speech": MLFeatureValue(multiArray: speech),
            "speech_lengths": MLFeatureValue(multiArray: lengths),
            "language": MLFeatureValue(multiArray: languageArr),
            "textnorm": MLFeatureValue(multiArray: textNormArr),
        ])
        let out = try model.prediction(from: input)
        guard let logits = out.featureValue(for: "ctc_logits")?.multiArrayValue else {
            throw ASRError.inferenceFailed("encoder missing 'ctc_logits' output")
        }
        // Logits length includes 4 query tokens; valid transcript frames ≈ t + 4.
        return (logits, t + 4)
    }

    private func pickBucket(forFrames frames: Int) -> Int {
        for b in buckets where b >= frames { return b }
        return buckets.last ?? 1800
    }

    private func decode(logits: MLMultiArray, validFrames: Int) -> String {
        let frames = min(validFrames, logits.shape[1].intValue)
        let vocabSize = logits.shape[2].intValue
        var ids: [Int] = []
        ids.reserveCapacity(frames)
        var prev = -1
        for f in 0..<frames {
            var best = 0
            var bestVal = -Float.greatestFiniteMagnitude
            for v in 0..<vocabSize {
                let val = logits[[0, f, v] as [NSNumber]].floatValue
                if val > bestVal {
                    bestVal = val
                    best = v
                }
            }
            if best != blankId && best != prev {
                ids.append(best)
            }
            prev = best
        }

        var pieces: [String] = []
        pieces.reserveCapacity(ids.count)
        for id in ids {
            guard id >= 0, id < vocabulary.count else { continue }
            pieces.append(vocabulary[id])
        }
        let raw = Self.detokenizeSentencePiece(pieces)
        return raw
            .replacingOccurrences(of: "<\\|[^|]*\\|>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func detokenizeSentencePiece(_ pieces: [String]) -> String {
        // vocab entries typically include leading ▁ for word pieces.
        var out = pieces.joined()
        out = out.replacingOccurrences(of: "▁", with: " ")
        out = out.replacingOccurrences(of: " ", with: " ")
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
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

    enum ASRError: Error, LocalizedError {
        case modelLoadFailed(String)
        case inferenceFailed(String)

        var errorDescription: String? {
            switch self {
            case .modelLoadFailed(let detail): return "SenseVoice Core ML load failed: \(detail)"
            case .inferenceFailed(let detail): return "SenseVoice inference failed: \(detail)"
            }
        }
    }
}
