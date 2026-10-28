import Foundation

/// Simple growable Int16 LE PCM buffer for smoke-test capture (not a fixed ring yet).
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

    func snapshot() -> (data: Data, streamStartMs: Int64, sampleRate: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (storage, streamStartMs, sampleRate)
    }

    func slice(startSample: Int, endSample: Int) -> Data {
        lock.lock()
        defer { lock.unlock() }
        let start = max(0, startSample * 2)
        let end = min(storage.count, endSample * 2)
        guard start < end else { return Data() }
        return storage.subdata(in: start..<end)
    }
}
