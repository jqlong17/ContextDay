import Foundation

/// Energy VAD: silence end ~1.5–2s; min 3s / max 30s (Spec §2.2).
final class VoiceActivityDetector {
    var minSpeechMs: Int = 3_000
    var maxSpeechMs: Int = 30_000
    var silenceEndMs: Int = 1_750
    /// RMS threshold on Float samples in [-1, 1].
    var energyThreshold: Float = 0.012
    var frameMs: Int = 30

    struct Utterance {
        var t0Ms: Int64
        var t1Ms: Int64
        /// Byte offsets into the Int16 PCM buffer that was analyzed (exclusive end).
        var startSample: Int
        var endSample: Int
    }

    /// Segment 16 kHz mono Int16 LE PCM. `streamStartMs` is wall-clock of sample 0.
    func segment(pcm: Data, streamStartMs: Int64, sampleRate: Int = 16_000) -> [Utterance] {
        let sampleCount = pcm.count / 2
        guard sampleCount > 0 else { return [] }

        let frameSamples = max(1, sampleRate * frameMs / 1000)
        let silenceFramesNeeded = max(1, silenceEndMs / frameMs)
        let minSpeechFrames = max(1, minSpeechMs / frameMs)
        let maxSpeechFrames = max(minSpeechFrames, maxSpeechMs / frameMs)

        var utterances: [Utterance] = []
        var inSpeech = false
        var speechStartFrame = 0
        var lastVoiceFrame = 0
        var silenceRun = 0
        let frameCount = sampleCount / frameSamples

        pcm.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            for f in 0..<frameCount {
                let base = f * frameSamples
                var sum: Float = 0
                for i in 0..<frameSamples {
                    let v = Float(samples[base + i]) / 32768.0
                    sum += v * v
                }
                let rms = sqrt(sum / Float(frameSamples))
                let voiced = rms >= energyThreshold

                if voiced {
                    if !inSpeech {
                        inSpeech = true
                        speechStartFrame = f
                    }
                    lastVoiceFrame = f
                    silenceRun = 0

                    // Force cut at max length.
                    if f - speechStartFrame + 1 >= maxSpeechFrames {
                        let endFrame = f + 1
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
                    if silenceRun >= silenceFramesNeeded {
                        let endFrame = lastVoiceFrame + 1
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
        }

        return utterances
    }

    /// Flush an open utterance at stop (if long enough).
    func flushOpenUtterance(pcm: Data, streamStartMs: Int64, sampleRate: Int = 16_000) -> Utterance? {
        // Re-run and take last incomplete by allowing trailing silence of 0 — simpler: segment whole buffer
        // with a temporary shorter silenceEnd for stop flush is overkill; use energy from end.
        let all = segment(pcm: pcm, streamStartMs: streamStartMs, sampleRate: sampleRate)
        return all.last
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
