import XCTest
@testable import ContextDay

/// SenseVoice Core ML load path — skip gracefully when models are absent (CI / fresh clone).
final class SenseVoiceASRTests: XCTestCase {
    func testLoadPathSkipsWhenModelsMissing() throws {
        let enc = ModelBundlePaths.senseVoiceEncoder
        let prep = ModelBundlePaths.senseVoicePreprocessor
        let vocab = ModelBundlePaths.senseVoiceVocab
        let present =
            enc.map { FileManager.default.fileExists(atPath: $0.path) } == true
            && prep.map { FileManager.default.fileExists(atPath: $0.path) } == true
            && vocab.map { FileManager.default.fileExists(atPath: $0.path) } == true

        guard present else {
            throw XCTSkip(
                "SenseVoice Core ML int8 missing under Resources/Models/SenseVoiceSmall_int8 — run Scripts/fetch-models.sh on Mac"
            )
        }

        let asr = SenseVoiceASR()
        try asr.loadModelIfNeeded()
        XCTAssertTrue(asr.isModelLoaded)
    }

    func testModelLoadFailedSurfacesWhenPathsBroken() {
        // Without overriding Bundle, we can only assert the error type exists and is Localizable
        // when models are missing from Bundle.main (typical in CI without fetch).
        let encOK = ModelBundlePaths.senseVoiceEncoder
            .map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        if encOK {
            // Models present — load-failure path covered by ops/manual; pass.
            return
        }
        let asr = SenseVoiceASR()
        XCTAssertThrowsError(try asr.loadModelIfNeeded()) { error in
            guard let asrError = error as? SenseVoiceASR.ASRError else {
                return XCTFail("expected ASRError.modelLoadFailed")
            }
            if case .modelLoadFailed(let detail) = asrError {
                XCTAssertFalse(detail.isEmpty)
                XCTAssertFalse(detail.lowercased().contains("onnx") && detail.contains("fallback"))
            } else {
                XCTFail("expected modelLoadFailed")
            }
        }
        XCTAssertFalse(asr.isModelLoaded)
    }
}
