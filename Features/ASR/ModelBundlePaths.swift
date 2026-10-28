import Foundation

/// Bundle-relative model locations under `Resources/Models/` (copied into the app).
enum ModelBundlePaths {
    static var modelsRoot: URL? {
        // Folder reference → Resources/Models/…
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Models", isDirectory: true),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return Bundle.main.url(forResource: "Models", withExtension: nil)
    }

    static var senseVoiceDirectory: URL? {
        modelsRoot?.appendingPathComponent("SenseVoiceSmall_int8", isDirectory: true)
    }

    static var senseVoiceEncoder: URL? {
        senseVoiceDirectory?.appendingPathComponent("SenseVoiceSmall_int8.mlmodelc", isDirectory: true)
    }

    static var senseVoicePreprocessor: URL? {
        senseVoiceDirectory?.appendingPathComponent("SenseVoicePreprocessor.mlmodelc", isDirectory: true)
    }

    static var senseVoiceVocab: URL? {
        senseVoiceDirectory?.appendingPathComponent("vocab.json")
    }

    static var yamnetONNX: URL? {
        modelsRoot?.appendingPathComponent("YAMNet/yamnet.onnx")
    }

    static var yamnetClassMap: URL? {
        modelsRoot?.appendingPathComponent("YAMNet/yamnet_class_map.csv")
    }
}
