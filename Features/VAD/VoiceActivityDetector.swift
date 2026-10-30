import Foundation

/// Energy VAD: silence end ~1.5–2s; min 3s / max 30s (Spec §2.2).
///
/// Uses a **noise-floor–relative** threshold (plus a lowered absolute floor) so quiet
/// Mac / USB mics after 48 kHz → 16 kHz Int16 convert still mark conversational
/// speech as voiced. A brittle absolute-only RMS (previously 0.012) could leave
/// `inSpeech` false forever → no silence-end and no max-30s cut → no ASR.
final class VoiceActivityDetector {
    var minSpeechMs: Int = 3_000
    var maxSpeechMs: Int = 30_000
    var silenceEndMs: Int = 1_750
    /// Absolute RMS floor on Float samples in [-1, 1]. Never voiced below this
    /// (digital / near silence). Also the flat-buffer fallback when dynamic range is low.
    /// Lowered from 0.012 — too high for quiet built-in/USB levels post-resample.
    var energyThreshold: Float = 0.0035
    /// Hard floor: frames below this are never voiced.
    var absoluteFloor: Float = 0.0012
    /// Speech if frame RMS ≥ max(absoluteFloor, noiseFloor × this), when the
    /// buffer has enough dynamic range to estimate a room floor.
    var noiseRelativeFactor: Float = 3.0
    /// Cap so a high noise-floor estimate cannot freeze VAD.
    var energyThresholdCap: Float = 0.02
    /// Peak / noiseFloor below this → treat buffer as flat; use `energyThreshold`.
    var flatDynamicRange: Float = 2.5
    var frameMs: Int = 30

    struct Utterance {
        var t0Ms: Int64
        var t1Ms: Int64
        /// Sample indices into the Int16 PCM buffer that was analyzed (exclusive end).
        var startSample: Int
        var endSample: Int
    }

    /// Mic triage: RMS / peak / voiced fraction for OSLog (no raw audio).
    struct EnergyProbe {
        var frameCount: Int
        var rmsMean: Float
        var rmsPeak: Float
        var noiseFloor: Float
        var effectiveThreshold: Float
        var voicedFraction: Float
    }

    /// Segment 16 kHz mono Int16 LE PCM. `streamStartMs` is wall-clock of sample 0.
    func segment(pcm: Data, streamStartMs: Int64, sampleRate: Int = 16_000) -> [Utterance] {
        let sampleCount = pcm.count / 2
        guard sampleCount > 0 else { return [] }

        let frameSamples = max(1, sampleRate * frameMs / 1000)
        let silenceFramesNeeded = max(1, silenceEndMs / frameMs)
        let minSpeechFrames = max(1, minSpeechMs / frameMs)
        let maxSpeechFrames = max(minSpeechFrames, maxSpeechMs / frameMs)
        let frameCount = sampleCount / frameSamples
        guard frameCount > 0 else { return [] }

        let rms = frameRMS(pcm: pcm, frameCount: frameCount, frameSamples: frameSamples)
        let thr = effectiveThreshold(rmsValues: rms)

        var utterances: [Utterance] = []
        var inSpeech = false
        var speechStartFrame = 0
        var lastVoiceFrame = 0
        var silenceRun = 0

        for f in 0..<frameCount {
            let voiced = rms[f] >= thr

            if voiced {
                if !inSpeech {
                    inSpeech = true
                    speechStartFrame = f
                }
                lastVoiceFrame = f
                silenceRun = 0

                // Force cut at max length (exact frame cap → ≤ sampleRate*maxSpeechMs/1000).
                // Must run whenever an open speech run hits max — including continuous voice
                // with no silence (regression: never wait for silence-end).
                if f - speechStartFrame + 1 >= maxSpeechFrames {
                    let endFrame = speechStartFrame + maxSpeechFrames
                    if endFrame - speechStartFrame >= minSpeechFrames {
                        utterances.append(
                            makeUtterance(
                                startFrame: speechStartFrame,
                                endFrame: endFrame,
                                frameSamples: frameSamples,
                                sampleRate: sampleRate,
                                streamStartMs: streamStartMs
                            )
                        )
                    }
                    inSpeech = false
                    silenceRun = 0
                }
            } else if inSpeech {
                silenceRun += 1
                let hitMax = f - speechStartFrame + 1 >= maxSpeechFrames
                // Silence-in-speech must also honor max — otherwise trailing silenceEnd
                // can defer the cut past preprocessor waveform limit (480_000 @16k).
                if silenceRun >= silenceFramesNeeded || hitMax {
                    let endFrame = hitMax
                        ? speechStartFrame + maxSpeechFrames
                        : lastVoiceFrame + 1
                    if endFrame - speechStartFrame >= minSpeechFrames {
                        utterances.append(
                            makeUtterance(
                                startFrame: speechStartFrame,
                                endFrame: endFrame,
                                frameSamples: frameSamples,
                                sampleRate: sampleRate,
                                streamStartMs: streamStartMs
                            )
                        )
                    }
                    inSpeech = false
                    silenceRun = 0
                }
            }
        }

        return utterances
    }

    /// Probe levels for triage logs (e.g. utt=0 while pcmBytes climbs).
    func probeEnergy(pcm: Data, sampleRate: Int = 16_000) -> EnergyProbe {
        let sampleCount = pcm.count / 2
        let frameSamples = max(1, sampleRate * frameMs / 1000)
        let frameCount = sampleCount / frameSamples
        guard frameCount > 0 else {
            return EnergyProbe(
                frameCount: 0, rmsMean: 0, rmsPeak: 0,
                noiseFloor: 0, effectiveThreshold: energyThreshold, voicedFraction: 0
            )
        }
        let rms = frameRMS(pcm: pcm, frameCount: frameCount, frameSamples: frameSamples)
        let thr = effectiveThreshold(rmsValues: rms)
        var sum: Float = 0
        var peak: Float = 0
        var voiced = 0
        for v in rms {
            sum += v
            if v > peak { peak = v }
            if v >= thr { voiced += 1 }
        }
        let noise = estimateNoiseFloor(rmsValues: rms)
        return EnergyProbe(
            frameCount: frameCount,
            rmsMean: sum / Float(frameCount),
            rmsPeak: peak,
            noiseFloor: noise,
            effectiveThreshold: thr,
            voicedFraction: Float(voiced) / Float(frameCount)
        )
    }

    /// Flush an open utterance at stop (if long enough).
    func flushOpenUtterance(pcm: Data, streamStartMs: Int64, sampleRate: Int = 16_000) -> Utterance? {
        // Re-run and take last incomplete by allowing trailing silence of 0 — simpler: segment whole buffer
        // with a temporary shorter silenceEnd for stop flush is overkill; use energy from end.
        let all = segment(pcm: pcm, streamStartMs: streamStartMs, sampleRate: sampleRate)
        return all.last
    }

    // MARK: - Energy

    private func frameRMS(pcm: Data, frameCount: Int, frameSamples: Int) -> [Float] {
        var out = [Float](repeating: 0, count: frameCount)
        pcm.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            for f in 0..<frameCount {
                let base = f * frameSamples
                var sum: Float = 0
                for i in 0..<frameSamples {
                    let v = Float(samples[base + i]) / 32768.0
                    sum += v * v
                }
                out[f] = sqrt(sum / Float(frameSamples))
            }
        }
        return out
    }

    /// ~10th percentile of frame RMS (room floor). Empty → 0.
    private func estimateNoiseFloor(rmsValues: [Float]) -> Float {
        guard !rmsValues.isEmpty else { return 0 }
        var sorted = rmsValues
        sorted.sort()
        let idx = max(0, min(sorted.count - 1, sorted.count / 10))
        return sorted[idx]
    }

    func effectiveThreshold(rmsValues: [Float]) -> Float {
        guard !rmsValues.isEmpty else { return energyThreshold }
        var peak: Float = 0
        for v in rmsValues {
            if v > peak { peak = v }
        }
        if peak < absoluteFloor {
            return absoluteFloor
        }
        let noise = estimateNoiseFloor(rmsValues: rmsValues)
        let denom = max(noise, 1e-7 as Float)
        let span = peak / denom
        if span < flatDynamicRange {
            // All near-silence or continuous quiet speech with no quiet reference:
            // use the (lowered) absolute default so conversational levels still segment.
            return max(absoluteFloor, energyThreshold)
        }
        let adaptive = noise * noiseRelativeFactor
        return min(energyThresholdCap, max(absoluteFloor, adaptive))
    }

    private func makeUtterance(
        startFrame: Int,
        endFrame: Int,
        frameSamples: Int,
        sampleRate: Int,
        streamStartMs: Int64
    ) -> Utterance {
        let startSample = startFrame * frameSamples
        let endSample = endFrame * frameSamples
        let t0 = streamStartMs + Int64(startSample * 1000 / sampleRate)
        let t1 = streamStartMs + Int64(endSample * 1000 / sampleRate)
        return Utterance(t0Ms: t0, t1Ms: max(t0 + 1, t1), startSample: startSample, endSample: endSample)
    }
}
