import Foundation

/// Process-local capture / UI health for self-check and `/health` (no transcript content).
final class RuntimeHealth: @unchecked Sendable {
    static let shared = RuntimeHealth()

    private let lock = NSLock()
    private var _uiWantsRecording = false
    private var _pipelineRunning = false
    private var _lastCaptureError: String?
    private var _lastCaptureErrorAtMs: Int64?

    private init() {}

    var uiWantsRecording: Bool {
        lock.lock(); defer { lock.unlock() }
        return _uiWantsRecording
    }

    var pipelineRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return _pipelineRunning
    }

    /// True when menu/UI recording flag disagrees with `CapturePipeline.isRunning`.
    var recordingDesync: Bool {
        lock.lock(); defer { lock.unlock() }
        return _uiWantsRecording != _pipelineRunning
    }

    var lastCaptureError: String? {
        lock.lock(); defer { lock.unlock() }
        return _lastCaptureError
    }

    var lastCaptureErrorAtMs: Int64? {
        lock.lock(); defer { lock.unlock() }
        return _lastCaptureErrorAtMs
    }

    func setUIWantsRecording(_ value: Bool) {
        lock.lock()
        _uiWantsRecording = value
        lock.unlock()
    }

    func setPipelineRunning(_ value: Bool) {
        lock.lock()
        _pipelineRunning = value
        lock.unlock()
    }

    func noteCaptureError(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lock.lock()
        _lastCaptureError = String(trimmed.prefix(240))
        _lastCaptureErrorAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        lock.unlock()
        AppLog.error(.capture, "last_error=\(trimmed.prefix(240))")
    }

    func clearCaptureError() {
        lock.lock()
        _lastCaptureError = nil
        _lastCaptureErrorAtMs = nil
        lock.unlock()
    }

    func snapshot() -> RuntimeHealthDTO {
        lock.lock()
        defer { lock.unlock() }
        return RuntimeHealthDTO(
            uiWantsRecording: _uiWantsRecording,
            pipelineRunning: _pipelineRunning,
            recordingDesync: _uiWantsRecording != _pipelineRunning,
            lastCaptureError: _lastCaptureError,
            lastCaptureErrorAtMs: _lastCaptureErrorAtMs
        )
    }
}

struct RuntimeHealthDTO: Codable, Equatable, Sendable {
    var uiWantsRecording: Bool
    var pipelineRunning: Bool
    var recordingDesync: Bool
    var lastCaptureError: String?
    var lastCaptureErrorAtMs: Int64?

    enum CodingKeys: String, CodingKey {
        case uiWantsRecording = "ui_wants_recording"
        case pipelineRunning = "pipeline_running"
        case recordingDesync = "recording_desync"
        case lastCaptureError = "last_capture_error"
        case lastCaptureErrorAtMs = "last_capture_error_at_ms"
    }
}
