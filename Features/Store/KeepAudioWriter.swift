import Foundation

/// Writes keep-audio evidence clips under `audio/YYYY-MM-DD/{mic|system}/`.
/// Spec on-disk default is `.opus`; MVP interim writes **16 kHz mono Linear PCM WAV**
/// via a pure-Swift RIFF header (no AVAudioFile / ExtAudioFile). AudioToolbox asserts
/// (SIGTRAP) on the previous CAF path are uncatchable in Swift — avoid that stack entirely.
enum KeepAudioWriter {
    static func writeIfEnabled(
        pcm16kMono: Data,
        segmentId: UUID,
        track: SegmentTrack,
        t0Ms: Int64,
        config: AppConfig
    ) -> String? {
        guard config.keepAudio else { return nil }
        let disk = DiskSpaceGuard.status()
        if disk.blockKeepAudio {
            AppLog.info(.keepAudio, "soft-fail open blocked reason=\(disk.warning ?? "low disk")")
            return nil
        }
        if config.audioScope == .speechOnly && config.gateEnabled {
            // Caller should only invoke for speech when scope is speech_only.
        }

        // Empty or odd-length Int16 PCM cannot form a valid WAV payload.
        guard !pcm16kMono.isEmpty, pcm16kMono.count % 2 == 0 else {
            AppLog.info(
                .keepAudio,
                "soft-fail empty_or_odd_pcm id=\(segmentId.uuidString.lowercased()) bytes=\(pcm16kMono.count)"
            )
            return nil
        }

        let day = dayFolderName(t0Ms: t0Ms)
        let relDir = "audio/\(day)/\(track.rawValue)"
        let absDir = AppPaths.recordsRoot.appendingPathComponent(relDir, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: absDir, withIntermediateDirectories: true)
        } catch {
            AppLog.info(.keepAudio, "soft-fail mkdir id=\(segmentId.uuidString.lowercased()) err=\(error.localizedDescription)")
            return nil
        }

        let fileName = "\(segmentId.uuidString.lowercased()).wav"
        let absURL = absDir.appendingPathComponent(fileName)
        do {
            try writeWAV(pcm16kMono: pcm16kMono, to: absURL)
            AppLog.info(
                .keepAudio,
                "wrote track=\(track.rawValue) id=\(segmentId.uuidString.lowercased()) bytes=\(pcm16kMono.count) path=\(relDir)/\(fileName)"
            )
            return "\(relDir)/\(fileName)"
        } catch {
            // Soft-fail: keep capture session alive; only skip this clip.
            AppLog.info(.keepAudio, "soft-fail write id=\(segmentId.uuidString.lowercased()) err=\(error.localizedDescription)")
            return nil
        }
    }

    private static func dayFolderName(t0Ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(t0Ms) / 1000.0)
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone.current
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }

    /// 16 kHz mono Int16 little-endian Linear PCM → classic RIFF WAVE.
    /// Pure Foundation I/O — never calls AVAudioFile / ExtAudioFileWrite.
    private static func writeWAV(pcm16kMono: Data, to url: URL) throws {
        let dataSize = UInt32(pcm16kMono.count)
        let sampleRate: UInt32 = 16_000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        // RIFF chunk size = file size minus 8 (RIFF + size fields).
        let riffChunkSize = UInt32(36) + dataSize

        var out = Data()
        out.reserveCapacity(44 + pcm16kMono.count)
        out.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        appendLE(&out, riffChunkSize)
        out.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        out.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        appendLE(&out, UInt32(16)) // PCM fmt chunk size
        appendLE(&out, UInt16(1)) // audio format = PCM
        appendLE(&out, channels)
        appendLE(&out, sampleRate)
        appendLE(&out, byteRate)
        appendLE(&out, blockAlign)
        appendLE(&out, bitsPerSample)
        out.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        appendLE(&out, dataSize)
        out.append(pcm16kMono)

        try out.write(to: url, options: .atomic)
    }

    private static func appendLE<T: FixedWidthInteger>(_ data: inout Data, _ value: T) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }
}
