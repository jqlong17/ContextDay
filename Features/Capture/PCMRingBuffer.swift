import Foundation

/// Int16 LE PCM buffer for capture.
/// - Variant A: growable `Data` soft-capped at ~10 min (legacy).
/// - Variant B: fixed-capacity ring ≈ 60s (Spec §3.2.1).
final class PCMRingBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let variant: PCMBufferVariant
    private let useFixedRing: Bool

    /// Growable path (A) and underlying storage for fixed ring (B).
    private var storage = Data()
    /// Oldest-byte index into `storage` when `useFixedRing`.
    private var head = 0
    /// Valid byte count when `useFixedRing` (always even).
    private var filled = 0
    private var capacityBytes: Int

    private(set) var streamStartMs: Int64 = 0
    private(set) var sampleRate: Int = 16_000
    /// High-water mark of filled bytes since last `reset` (A/B metric).
    private(set) var peakFilledBytes: Int = 0

    init(variant: PCMBufferVariant = PCMBufferPolicy.resolveVariant()) {
        self.variant = variant
        self.useFixedRing = PCMBufferPolicy.usesFixedRing(variant)
        self.sampleRate = 16_000
        self.capacityBytes = PCMBufferPolicy.capacityBytes(sampleRate: 16_000, variant: variant)
        if useFixedRing {
            storage = Data(count: capacityBytes)
        }
    }

    var sampleCount: Int {
        lock.lock(); defer { lock.unlock() }
        return filledBytesLocked() / 2
    }

    var resolvedVariant: PCMBufferVariant { variant }

    func metrics() -> PCMBufferMetrics {
        lock.lock()
        defer { lock.unlock() }
        return PCMBufferMetrics(
            variant: variant.rawValue,
            sampleRate: sampleRate,
            filledBytes: filledBytesLocked(),
            capacityBytes: capacityBytes,
            peakFilledBytes: peakFilledBytes,
            streamStartMs: streamStartMs
        )
    }

    func reset(streamStartMs: Int64, sampleRate: Int = 16_000) {
        lock.lock()
        defer { lock.unlock() }
        self.sampleRate = max(1, sampleRate)
        self.capacityBytes = PCMBufferPolicy.capacityBytes(sampleRate: self.sampleRate, variant: variant)
        self.streamStartMs = streamStartMs
        self.peakFilledBytes = 0
        head = 0
        filled = 0
        if useFixedRing {
            if storage.count != capacityBytes {
                storage = Data(count: capacityBytes)
            } else {
                storage.resetBytes(in: 0..<storage.count)
            }
        } else {
            storage.removeAll(keepingCapacity: true)
        }
    }

    func append(int16LE data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        if useFixedRing {
            appendFixedLocked(data)
        } else {
            appendGrowableLocked(data)
        }
    }

    /// Point-in-time contiguous copy under lock. Callers may slice on another queue;
    /// returning shared storage races with append/trim and can SIGTRAP inside `Data.subdata`.
    func snapshot() -> (data: Data, streamStartMs: Int64, sampleRate: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (linearizedLocked(), streamStartMs, sampleRate)
    }

    func slice(startSample: Int, endSample: Int) -> Data {
        lock.lock()
        defer { lock.unlock() }
        let pcm = linearizedLocked()
        return PCMInt16Slice.subdata(pcm: pcm, startSample: startSample, endSample: endSample) ?? Data()
    }

    // MARK: - Locked helpers

    private func filledBytesLocked() -> Int {
        useFixedRing ? filled : storage.count
    }

    private func appendGrowableLocked(_ data: Data) {
        var chunk = data
        if chunk.count % 2 != 0 {
            chunk = chunk.subdata(in: 0..<(chunk.count - 1))
        }
        guard !chunk.isEmpty else { return }
        storage.append(chunk)
        let maxBytes = capacityBytes
        if storage.count > maxBytes {
            let drop = storage.count - maxBytes
            let dropAligned = drop - (drop % 2)
            if dropAligned > 0 {
                storage.removeFirst(dropAligned)
                let droppedSamples = dropAligned / 2
                streamStartMs += Int64(droppedSamples * 1000 / max(1, sampleRate))
            }
        }
        peakFilledBytes = max(peakFilledBytes, storage.count)
    }

    private func appendFixedLocked(_ data: Data) {
        let sr = max(1, sampleRate)
        var nbytes = data.count - (data.count % 2)
        guard nbytes > 0, capacityBytes >= 2 else { return }

        data.withUnsafeBytes { srcRaw in
            guard let base = srcRaw.bindMemory(to: UInt8.self).baseAddress else { return }
            var srcOffset = 0

            if nbytes > capacityBytes {
                let skip = nbytes - capacityBytes
                let skipAligned = skip - (skip % 2)
                if filled > 0 {
                    streamStartMs += Int64((filled / 2) * 1000 / sr)
                }
                streamStartMs += Int64((skipAligned / 2) * 1000 / sr)
                srcOffset = skipAligned
                nbytes = capacityBytes
                head = 0
                filled = 0
            } else {
                let overflow = filled + nbytes - capacityBytes
                if overflow > 0 {
                    let dropAligned = overflow - (overflow % 2)
                    if dropAligned > 0 {
                        head = (head + dropAligned) % capacityBytes
                        filled -= dropAligned
                        streamStartMs += Int64((dropAligned / 2) * 1000 / sr)
                    }
                }
            }

            var remaining = nbytes
            var offset = srcOffset
            while remaining > 0 {
                let tail = (head + filled) % capacityBytes
                let contiguous = min(remaining, capacityBytes - tail)
                for i in 0..<contiguous {
                    storage[tail + i] = base[offset + i]
                }
                filled += contiguous
                offset += contiguous
                remaining -= contiguous
            }
        }
        peakFilledBytes = max(peakFilledBytes, filled)
    }

    private func linearizedLocked() -> Data {
        if !useFixedRing {
            return Data(storage)
        }
        if filled == 0 { return Data() }
        var out = Data(count: filled)
        out.withUnsafeMutableBytes { dstRaw in
            guard let dst = dstRaw.bindMemory(to: UInt8.self).baseAddress else { return }
            let first = min(filled, capacityBytes - head)
            storage.copyBytes(to: dst, from: head..<(head + first))
            if filled > first {
                storage.copyBytes(to: dst + first, from: 0..<(filled - first))
            }
        }
        return out
    }
}

/// Int16 LE sample-index → byte slice. Returns nil on empty / OOB (never traps).
enum PCMInt16Slice {
    static func subdata(pcm: Data, startSample: Int, endSample: Int) -> Data? {
        let sampleCount = pcm.count / 2
        guard startSample >= 0, endSample > startSample, startSample < sampleCount else {
            return nil
        }
        let clampedEnd = min(endSample, sampleCount)
        guard clampedEnd > startSample else { return nil }
        let start = startSample * 2
        let end = clampedEnd * 2
        guard start < end, end <= pcm.count else { return nil }
        return pcm.subdata(in: start..<end)
    }
}

/// XCTest / script helper: feed synthetic silence and report peak metrics for A vs B.
enum PCMBufferABHarness {
    /// Append `seconds` of Int16 silence @ `sampleRate` in `chunkMs` chunks; return metrics.
    static func fillSilence(
        variant: PCMBufferVariant,
        seconds: Double,
        sampleRate: Int = 16_000,
        chunkMs: Int = 100,
        streamStartMs: Int64 = 1_000_000
    ) -> PCMBufferMetrics {
        let ring = PCMRingBuffer(variant: variant)
        ring.reset(streamStartMs: streamStartMs, sampleRate: sampleRate)
        let chunkSamples = max(1, sampleRate * chunkMs / 1000)
        let chunk = Data(count: chunkSamples * 2)
        let totalSamples = Int(seconds * Double(sampleRate))
        var written = 0
        while written < totalSamples {
            let n = min(chunkSamples, totalSamples - written)
            if n == chunkSamples {
                ring.append(int16LE: chunk)
            } else {
                ring.append(int16LE: Data(count: n * 2))
            }
            written += n
        }
        return ring.metrics()
    }

    /// Compare peak filled bytes: pass if B ≤ A × `ratio` (default 0.15 ≈ 10× smaller at A soft-cap).
    static func peakRatioPass(a: PCMBufferMetrics, b: PCMBufferMetrics, maxRatio: Double = 0.15) -> Bool {
        guard a.peakFilledBytes > 0 else { return false }
        return Double(b.peakFilledBytes) <= Double(a.peakFilledBytes) * maxRatio
    }
}
