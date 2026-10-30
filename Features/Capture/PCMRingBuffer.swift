import Foundation

/// Growable Int16 LE PCM buffer for capture (soft-capped; not a fixed ring yet).
final class PCMRingBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()
    private(set) var streamStartMs: Int64 = 0
    private(set) var sampleRate: Int = 16_000

    var sampleCount: Int {
        lock.lock(); defer { lock.unlock() }
        return storage.count / 2
    }

    func reset(streamStartMs: Int64, sampleRate: Int = 16_000) {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll(keepingCapacity: true)
        self.streamStartMs = streamStartMs
        self.sampleRate = sampleRate
    }

    func append(int16LE data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        storage.append(data)
        // Cap ~10 minutes to bound RAM during long smoke tests.
        let maxBytes = sampleRate * 2 * 60 * 10
        if storage.count > maxBytes {
            let drop = storage.count - maxBytes
            storage.removeFirst(drop - (drop % 2))
            let droppedSamples = drop / 2
            streamStartMs += Int64(droppedSamples * 1000 / sampleRate)
        }
    }

    /// Point-in-time copy under lock. Callers may slice on another queue; returning shared
    /// `storage` races with `append`/`removeFirst` and can SIGTRAP inside `Data.subdata`.
    func snapshot() -> (data: Data, streamStartMs: Int64, sampleRate: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (Data(storage), streamStartMs, sampleRate)
    }

    func slice(startSample: Int, endSample: Int) -> Data {
        lock.lock()
        defer { lock.unlock() }
        return PCMInt16Slice.subdata(pcm: storage, startSample: startSample, endSample: endSample) ?? Data()
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
