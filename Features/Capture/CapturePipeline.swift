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
    /// Wall-clock [t0,t1] already sent to ASR — survives ring trim (sample-index dedupe does not).
    private var emittedMic: [(Int64, Int64)] = []
    private var emittedSystem: [(Int64, Int64)] = []
    /// Rate-limit empty-buffer / no-utt triage logs on the process queue.
    private var processTick: Int = 0
    private var converter: AVAudioConverter?
    private let targetSampleRate: Double = 16_000
    private var systemCapture: AnyObject?

    var onStatus: ((String) -> Void)?

    func start() {
        guard !isRunning else { return }
        AppLog.info(.capture, "start requested")
        requestMicAccess { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                if granted {
                    self.startAfterPermission()
                } else {
                    PermissionStatus.logSnapshot(reason: "capture_fail_mic")
                    RuntimeHealth.shared.noteCaptureError("Microphone permission denied")
                    RuntimeHealth.shared.setPipelineRunning(false)
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
        processTick = 0
        let sessionStart = Int64(Date().timeIntervalSince1970 * 1000)
        micBuffer.reset(streamStartMs: sessionStart, sampleRate: Int(targetSampleRate))
        systemBuffer.reset(streamStartMs: sessionStart, sampleRate: Int(targetSampleRate))

        do { try gate.loadModelIfNeeded() } catch {
            AppLog.error(.gate, "load failed: \(error.localizedDescription)")
            onStatus?("YAMNet load failed: \(error.localizedDescription)")
        }
        do { try asr.loadModelIfNeeded() } catch {
            AppLog.error(.asr, "load failed: \(error.localizedDescription)")
            onStatus?("SenseVoice Core ML load failed: \(error.localizedDescription)")
        }

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            PermissionStatus.logSnapshot(reason: "capture_fail_input")
            RuntimeHealth.shared.noteCaptureError("Microphone unavailable / permission denied")
            RuntimeHealth.shared.setPipelineRunning(false)
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
            RuntimeHealth.shared.setPipelineRunning(true)
            RuntimeHealth.shared.clearCaptureError()
            startProcessingLoop()
            onStatus?("Recording (mic)")
            AppLog.info(.capture, "mic started sampleRate=\(Int(inputFormat.sampleRate)) ch=\(Int(inputFormat.channelCount))")
        } catch {
            input.removeTap(onBus: 0)
            PermissionStatus.logSnapshot(reason: "capture_fail_engine")
            RuntimeHealth.shared.noteCaptureError("Capture start failed: \(error.localizedDescription)")
            RuntimeHealth.shared.setPipelineRunning(false)
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
                PermissionStatus.logSnapshot(reason: "capture_fail_system")
                RuntimeHealth.shared.noteCaptureError(msg)
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
        RuntimeHealth.shared.setPipelineRunning(false)
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
        AppLog.info(.capture, "stopped")
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
        if track == .mic { processTick += 1 }
        guard snap.data.count > 3200 else {
            if track == .mic && processTick % 10 == 1 {
                AppLog.info(
                    .vad,
                    "process track=\(track.rawValue) pcmBytes=\(snap.data.count) (below VAD threshold) tick=\(processTick)"
                )
            }
            return
        }
        let utterances = vad.segment(pcm: snap.data, streamStartMs: snap.streamStartMs, sampleRate: snap.sampleRate)
        AppLog.debug(
            .vad,
            "track=\(track.rawValue) utterances=\(utterances.count) pcmBytes=\(snap.data.count) forceFlush=\(forceFlush)"
        )
        var skippedDup = 0
        var skippedPending = 0
        var sent = 0
        for utt in utterances {
            // Single-flight by wall-clock cover (Spec v0.3.24). Must NOT use overlap/min(dur)
            // (`isNearDuplicateInterval`) — that treats a longer refinement of a short prior
            // emit as a dup and can starve all later ASR. Sample-index ±800 still fails after ring trim.
            if emitted.contains(where: {
                SegmentMerger.isAlreadyEmittedInterval(a0: $0.0, a1: $0.1, b0: utt.t0Ms, b1: utt.t1Ms)
            }) {
                skippedDup += 1
                continue
            }
            let samplesNow = snap.data.count / 2
            if !forceFlush && utt.endSample > samplesNow - snap.sampleRate {
                skippedPending += 1
                continue
            }
            emitted.append((utt.t0Ms, utt.t1Ms))
            sent += 1
            handleUtterance(utt, pcm: snap.data, track: track)
        }
        let interesting = sent > 0 || skippedDup > 0 || !utterances.isEmpty
        if interesting || (track == .mic && processTick % 10 == 1) {
            var line =
                "process track=\(track.rawValue) utt=\(utterances.count) sent=\(sent) "
                + "skip_dup=\(skippedDup) skip_pending=\(skippedPending) "
                + "pcmBytes=\(snap.data.count) emittedN=\(emitted.count) forceFlush=\(forceFlush)"
            // When mic produces no utterances, attach RMS/peak/voicedFraction so energy stalls
            // (threshold too high / near-silence convert) are obvious — never log raw audio.
            if track == .mic && utterances.isEmpty {
                let probe = vad.probeEnergy(pcm: snap.data, sampleRate: snap.sampleRate)
                line += String(
                    format: " rms=%.4f peak=%.4f thr=%.4f noise=%.4f voicedFrac=%.2f frames=%d",
                    probe.rmsMean, probe.rmsPeak, probe.effectiveThreshold,
                    probe.noiseFloor, probe.voicedFraction, probe.frameCount
                )
            }
            AppLog.info(.vad, line)
        }
        // Drop emission records older than the ring's stream start (already trimmed away).
        let pruned = emitted.filter { $0.1 >= snap.streamStartMs - 2_000 }
        if track == .mic { emittedMic = pruned } else { emittedSystem = pruned }
    }

    private func handleUtterance(_ utt: VoiceActivityDetector.Utterance, pcm: Data, track: SegmentTrack) {
        guard let slice = PCMInt16Slice.subdata(
            pcm: pcm, startSample: utt.startSample, endSample: utt.endSample
        ) else {
            AppLog.error(
                .capture,
                "skip utterance bad PCM range track=\(track.rawValue) "
                    + "startSample=\(utt.startSample) endSample=\(utt.endSample) pcmBytes=\(pcm.count)"
            )
            return
        }
        let durationMs = max(0, utt.t1Ms - utt.t0Ms)
        let cfg = AppConfigStore.load()

        var gateLabel: GateLabel?
        if cfg.gateEnabled {
            // Per-track only: system Music must never mute mic ASR (Spec §1.4 dual-rail).
            AppLog.info(
                .gate,
                "classify begin track=\(track.rawValue) dur_ms=\(durationMs) pcmBytes=\(slice.count)"
            )
            let result = gate.classify(
                track: track, pcmWindow: slice,
                windowStartMs: utt.t0Ms, windowEndMs: utt.t1Ms
            )
            gateLabel = result.label
            let action = result.label == .speech ? "send_asr" : "skip_asr"
            AppLog.info(
                .gate,
                "per-track gate track=\(track.rawValue) label=\(result.label.rawValue) action=\(action) "
                    + "speech=\(String(format: "%.3f", result.speechScore)) "
                    + "music=\(String(format: "%.3f", result.musicScore)) "
                    + "dur_ms=\(durationMs) scope=this_track_only"
            )
            if result.label != .speech {
                return
            }
        }

        do {
            let transcript = try asr.transcribe(pcm16kMono: slice)
            let text = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                AppLog.debug(.asr, "empty transcript track=\(track.rawValue) dur_ms=\(durationMs)")
                return
            }
            let id = UUID()
            var audioPath: String?
            if cfg.keepAudio {
                let disk = DiskSpaceGuard.status()
                if disk.blockKeepAudio {
                    let reason = disk.warning ?? "Low disk — keep-audio blocked"
                    AppLog.info(.keepAudio, "soft-fail blocked reason=\(reason)")
                    onStatus?(reason)
                } else {
                    // speech_only already filtered by gate when enabled
                    audioPath = KeepAudioWriter.writeIfEnabled(
                        pcm16kMono: slice, segmentId: id, track: track, t0Ms: utt.t0Ms, config: cfg
                    )
                }
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
            // Privacy: UI may show a short preview; logs only get id + length.
            onStatus?("Saved[\(track.rawValue)]: \(text.prefix(32))…")
            AppLog.info(
                .capture,
                "saved track=\(track.rawValue) id=\(id.uuidString.lowercased()) chars=\(text.count) dur_ms=\(durationMs) keep_audio=\(audioPath != nil)"
            )
        } catch {
            RuntimeHealth.shared.noteCaptureError("ASR/store failed: \(error.localizedDescription)")
            onStatus?("ASR failed: \(error.localizedDescription)")
            AppLog.error(.asr, "ASR/store failed track=\(track.rawValue) dur_ms=\(durationMs) err=\(error.localizedDescription)")
        }
    }
}
