import AVFoundation
import Foundation

/// Mic capture → 16 kHz mono Int16 ring buffer → VAD → YAMNet gate → SenseVoice → Store.
/// System audio (ScreenCaptureKit) remains a later enhancement; mic is enough for smoke tests.
final class CapturePipeline {
    enum Track {
        case mic
        case system
    }

    private(set) var isRunning = false

    private let engine = AVAudioEngine()
    private let buffer = PCMRingBuffer()
    private let vad = VoiceActivityDetector()
    private let gate = YamNetGate()
    private let asr = SenseVoiceASR()
    private let store = SegmentStore.shared
    private let config = AppConfigStore.self

    private var processQueue = DispatchQueue(label: "app.contextday.capture.process")
    private var processTimer: DispatchSourceTimer?
    private var emittedRanges: [(Int, Int)] = [] // sample ranges already committed
    private var converter: AVAudioConverter?
    private let targetSampleRate: Double = 16_000

    var onStatus: ((String) -> Void)?

    func start() {
        guard !isRunning else { return }
        requestMicAccess { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                if granted {
                    self.startAfterPermission()
                } else {
                    NSLog("ContextDay Capture: microphone permission denied")
                    self.onStatus?("Microphone permission denied — enable in System Settings")
                }
            }
        }
    }

    private func requestMicAccess(completion: @escaping (Bool) -> Void) {
        if #available(macOS 14.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                completion(granted)
            }
        } else {
            AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
        }
    }

    private func startAfterPermission() {
        guard !isRunning else { return }
        emittedRanges.removeAll()

        let sessionStart = Int64(Date().timeIntervalSince1970 * 1000)
        buffer.reset(streamStartMs: sessionStart, sampleRate: Int(targetSampleRate))

        do {
            try gate.loadModelIfNeeded()
        } catch {
            NSLog("ContextDay Capture: YAMNet load warning — \(error.localizedDescription)")
            onStatus?("YAMNet load failed: \(error.localizedDescription)")
        }
        do {
            try asr.loadModelIfNeeded()
        } catch {
            NSLog("ContextDay Capture: SenseVoice load FAILED — \(error.localizedDescription)")
            onStatus?("SenseVoice Core ML load failed: \(error.localizedDescription)")
            // Still start capture so user sees the error path; ASR will fail per-utterance.
        }

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            NSLog("ContextDay Capture: invalid input format — grant Microphone permission?")
            onStatus?("Microphone unavailable / permission denied")
            return
        }

        let mono16 = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        )!
        converter = AVAudioConverter(from: inputFormat, to: mono16)

        input.removeTap(onBus: 0)
        let bufferSize: AVAudioFrameCount = 2048
        input.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] pcm, _ in
            self?.appendConverted(pcm, to: mono16)
        }

        do {
            try engine.start()
            isRunning = true
            startProcessingLoop()
            NSLog("ContextDay Capture: mic started @ \(inputFormat.sampleRate) Hz → 16 kHz mono")
            onStatus?("Recording (mic)")
        } catch {
            input.removeTap(onBus: 0)
            NSLog("ContextDay Capture: engine start failed — \(error.localizedDescription)")
            onStatus?("Capture start failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        processTimer?.cancel()
        processTimer = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        // Final pass for trailing speech.
        processQueue.async { [weak self] in
            self?.processBuffer(forceFlush: true)
        }
        NSLog("ContextDay Capture: stopped")
        onStatus?("Stopped")
    }

    // MARK: - Audio

    private func appendConverted(_ pcm: AVAudioPCMBuffer, to format: AVAudioFormat) {
        guard let converter else { return }
        let ratio = format.sampleRate / pcm.format.sampleRate
        let capacity = AVAudioFrameCount(Double(pcm.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
        var error: NSError?
        var consumed = false
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return pcm
        }
        if status == .error {
            return
        }
        guard out.frameLength > 0, let channels = out.int16ChannelData else { return }
        let byteCount = Int(out.frameLength) * MemoryLayout<Int16>.size
        let data = Data(bytes: channels[0], count: byteCount)
        buffer.append(int16LE: data)
    }

    private func startProcessingLoop() {
        let timer = DispatchSource.makeTimerSource(queue: processQueue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            self?.processBuffer(forceFlush: false)
        }
        timer.resume()
        processTimer = timer
    }

    private func processBuffer(forceFlush: Bool) {
        let snap = buffer.snapshot()
        guard snap.data.count > 3200 else { return } // ~0.1s

        let utterances = vad.segment(pcm: snap.data, streamStartMs: snap.streamStartMs, sampleRate: snap.sampleRate)
        for utt in utterances {
            let key = (utt.startSample, utt.endSample)
            if emittedRanges.contains(where: { abs($0.0 - key.0) < 800 && abs($0.1 - key.1) < 800 }) {
                continue
            }
            // Skip still-open trailing edge unless flushing.
            let samplesNow = snap.data.count / 2
            if !forceFlush && utt.endSample > samplesNow - snap.sampleRate {
                continue
            }
            emittedRanges.append(key)
            handleUtterance(utt, pcm: snap.data)
        }
    }

    private func handleUtterance(_ utt: VoiceActivityDetector.Utterance, pcm: Data) {
        let start = max(0, utt.startSample * 2)
        let end = min(pcm.count, utt.endSample * 2)
        guard start < end else { return }
        let slice = pcm.subdata(in: start..<end)

        let cfg = config.load()
        var gateLabel: GateLabel? = nil
        if cfg.gateEnabled {
            // ~5s gate window: use utterance audio (may be longer; YAMNet aggregates frames).
            let result = gate.classify(
                track: .mic,
                pcmWindow: slice,
                windowStartMs: utt.t0Ms,
                windowEndMs: utt.t1Ms
            )
            gateLabel = result.label
            if result.label == .music {
                NSLog("ContextDay Capture: skip ASR (music) \(utt.t0Ms)-\(utt.t1Ms)")
                // Optionally still store without text for timeline evidence — Spec: not sent to ASR.
                // Smoke success focuses on Speech→text; skip insert for pure music.
                return
            }
            if result.label == .other {
                // Other: do not send to ASR when gate is on (only Speech).
                NSLog("ContextDay Capture: skip ASR (other) \(utt.t0Ms)-\(utt.t1Ms)")
                return
            }
        }

        do {
            let transcript = try asr.transcribe(pcm16kMono: slice)
            let text = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                NSLog("ContextDay Capture: empty transcript for \(utt.t0Ms)-\(utt.t1Ms)")
                return
            }
            let segment = Segment(
                id: UUID(),
                track: .mic,
                t0Ms: utt.t0Ms,
                t1Ms: utt.t1Ms,
                tzAtCapture: TimeZone.current.identifier,
                text: text,
                gateLabel: gateLabel ?? (cfg.gateEnabled ? .speech : nil),
                audioPath: nil,
                sourceSegmentIds: [],
                createdAtMs: Int64(Date().timeIntervalSince1970 * 1000),
                mergedAtMs: nil,
                mergeGapMs: nil,
                asrModelId: transcript.modelId,
                asrModelVersion: transcript.modelVersion
            )
            try store.insertSegment(segment)
            NSLog("ContextDay Capture: saved segment «\(text.prefix(48))»")
            onStatus?("Saved: \(text.prefix(32))…")
        } catch {
            NSLog("ContextDay Capture: ASR/store failed — \(error.localizedDescription)")
            onStatus?("ASR failed: \(error.localizedDescription)")
        }
    }
}
