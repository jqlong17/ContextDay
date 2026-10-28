import AVFoundation
import Foundation
import ScreenCaptureKit

/// Dual-rail capture (mic + optional system) → VAD → YAMNet → SenseVoice → Store (+ optional keep-audio).
final class CapturePipeline {
    private(set) var isRunning = false

    private let engine = AVAudioEngine()
    private let micBuffer = PCMRingBuffer()
    private let systemBuffer = PCMRingBuffer()
    private let vad = VoiceActivityDetector()
    private let gate = YamNetGate()
    private let asr = SenseVoiceASR()
    private let store = SegmentStore.shared

    private var processQueue = DispatchQueue(label: "app.contextday.capture.process")
    private var processTimer: DispatchSourceTimer?
    private var emittedMic: [(Int, Int)] = []
    private var emittedSystem: [(Int, Int)] = []
    private var converter: AVAudioConverter?
    private let targetSampleRate: Double = 16_000
    private var systemCapture: AnyObject?

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
            AVAudioApplication.requestRecordPermission { granted in completion(granted) }
        } else {
            AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
        }
    }

    private func startAfterPermission() {
        guard !isRunning else { return }
        emittedMic.removeAll()
        emittedSystem.removeAll()
        let sessionStart = Int64(Date().timeIntervalSince1970 * 1000)
        micBuffer.reset(streamStartMs: sessionStart, sampleRate: Int(targetSampleRate))
        systemBuffer.reset(streamStartMs: sessionStart, sampleRate: Int(targetSampleRate))

        do { try gate.loadModelIfNeeded() } catch {
            onStatus?("YAMNet load failed: \(error.localizedDescription)")
        }
        do { try asr.loadModelIfNeeded() } catch {
            onStatus?("SenseVoice Core ML load failed: \(error.localizedDescription)")
        }

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
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
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] pcm, _ in
            self?.appendConverted(pcm, to: mono16, into: self?.micBuffer)
        }

        do {
            try engine.start()
            isRunning = true
            startProcessingLoop()
            onStatus?("Recording (mic)")
            NSLog("ContextDay Capture: mic started")
        } catch {
            input.removeTap(onBus: 0)
            onStatus?("Capture start failed: \(error.localizedDescription)")
            return
        }

        let cfg = AppConfigStore.load()
        if cfg.captureSystemAudio {
            startSystemAudio()
        }
    }

    private func startSystemAudio() {
        if #available(macOS 13.0, *) {
            let capture = SystemAudioCapture()
            capture.onPCM = { [weak self] data in
                self?.systemBuffer.append(int16LE: data)
            }
            capture.onError = { [weak self] msg in
                self?.onStatus?(msg)
            }
            systemCapture = capture
            Task { await capture.start() }
        } else {
            onStatus?("System audio requires macOS 13+")
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        processTimer?.cancel()
        processTimer = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        if #available(macOS 13.0, *), let capture = systemCapture as? SystemAudioCapture {
            capture.stop()
        }
        systemCapture = nil
        processQueue.async { [weak self] in
            self?.processTrack(.mic, forceFlush: true)
            self?.processTrack(.system, forceFlush: true)
        }
        onStatus?("Stopped")
    }

    private func appendConverted(_ pcm: AVAudioPCMBuffer, to format: AVAudioFormat, into ring: PCMRingBuffer?) {
        guard let converter, let ring else { return }
        let ratio = format.sampleRate / pcm.format.sampleRate
        let capacity = AVAudioFrameCount(Double(pcm.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
        var error: NSError?
        var consumed = false
        _ = converter.convert(to: out, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return pcm
        }
        guard out.frameLength > 0, let channels = out.int16ChannelData else { return }
        let data = Data(bytes: channels[0], count: Int(out.frameLength) * MemoryLayout<Int16>.size)
        ring.append(int16LE: data)
    }

    private func startProcessingLoop() {
        let timer = DispatchSource.makeTimerSource(queue: processQueue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            self?.processTrack(.mic, forceFlush: false)
            self?.processTrack(.system, forceFlush: false)
        }
        timer.resume()
        processTimer = timer
    }

    private func processTrack(_ track: SegmentTrack, forceFlush: Bool) {
        let ring = track == .mic ? micBuffer : systemBuffer
        var emitted = track == .mic ? emittedMic : emittedSystem
        let snap = ring.snapshot()
        guard snap.data.count > 3200 else { return }
        let utterances = vad.segment(pcm: snap.data, streamStartMs: snap.streamStartMs, sampleRate: snap.sampleRate)
        for utt in utterances {
            if emitted.contains(where: { abs($0.0 - utt.startSample) < 800 && abs($0.1 - utt.endSample) < 800 }) {
                continue
            }
            let samplesNow = snap.data.count / 2
            if !forceFlush && utt.endSample > samplesNow - snap.sampleRate { continue }
            emitted.append((utt.startSample, utt.endSample))
            handleUtterance(utt, pcm: snap.data, track: track)
        }
        if track == .mic { emittedMic = emitted } else { emittedSystem = emitted }
    }

    private func handleUtterance(_ utt: VoiceActivityDetector.Utterance, pcm: Data, track: SegmentTrack) {
        let start = max(0, utt.startSample * 2)
        let end = min(pcm.count, utt.endSample * 2)
        guard start < end else { return }
        let slice = pcm.subdata(in: start..<end)
        let cfg = AppConfigStore.load()

        var gateLabel: GateLabel?
        if cfg.gateEnabled {
            let result = gate.classify(
                track: track, pcmWindow: slice,
                windowStartMs: utt.t0Ms, windowEndMs: utt.t1Ms
            )
            gateLabel = result.label
            if result.label != .speech {
                NSLog("ContextDay Capture: skip ASR (\(result.label.rawValue)) track=\(track.rawValue)")
                return
            }
        }

        do {
            let transcript = try asr.transcribe(pcm16kMono: slice)
            let text = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let id = UUID()
            var audioPath: String?
            if cfg.keepAudio {
                // speech_only already filtered by gate when enabled
                audioPath = KeepAudioWriter.writeIfEnabled(
                    pcm16kMono: slice, segmentId: id, track: track, t0Ms: utt.t0Ms, config: cfg
                )
            }
            let segment = Segment(
                id: id,
                track: track,
                t0Ms: utt.t0Ms,
                t1Ms: utt.t1Ms,
                tzAtCapture: TimeZone.current.identifier,
                text: text,
                gateLabel: gateLabel ?? (cfg.gateEnabled ? .speech : nil),
                audioPath: audioPath,
                sourceSegmentIds: [],
                createdAtMs: Int64(Date().timeIntervalSince1970 * 1000),
                mergedAtMs: nil,
                mergeGapMs: nil,
                asrModelId: transcript.modelId,
                asrModelVersion: transcript.modelVersion
            )
            _ = try store.insertSegment(segment, mergeGapMs: cfg.mergeGapMs)
            onStatus?("Saved[\(track.rawValue)]: \(text.prefix(32))…")
            NSLog("ContextDay Capture: saved \(track.rawValue) «\(text.prefix(48))»")
        } catch {
            onStatus?("ASR failed: \(error.localizedDescription)")
            NSLog("ContextDay Capture: ASR/store failed — \(error.localizedDescription)")
        }
    }
}
