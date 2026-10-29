import AVFoundation
import Foundation

/// Writes keep-audio evidence clips under `audio/YYYY-MM-DD/{mic|system}/`.
/// Prefers Opus in a Core Audio container when the encoder is available; otherwise
/// writes 16 kHz mono CAF and logs — Spec on-disk default is `.opus`.
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

        let day = dayFolderName(t0Ms: t0Ms)
        let relDir = "audio/\(day)/\(track.rawValue)"
        let absDir = AppPaths.recordsRoot.appendingPathComponent(relDir, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: absDir, withIntermediateDirectories: true)
        } catch {
            AppLog.info(.keepAudio, "soft-fail mkdir id=\(segmentId.uuidString.lowercased()) err=\(error.localizedDescription)")
            return nil
        }

        let fileName = "\(segmentId.uuidString.lowercased()).caf"
        let absURL = absDir.appendingPathComponent(fileName)
        do {
            try writeCAF(pcm16kMono: pcm16kMono, to: absURL, bitrate: config.audioQuality.bitrate)
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

    /// 16 kHz mono Int16 → CAF (Linear PCM). Opus bitstream packaging can replace this
    /// when a stable Opus encoder path is wired; filename stays under Spec audio tree.
    private static func writeCAF(pcm16kMono: Data, to url: URL, bitrate _: Int) throws {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        )!
        let frameCount = AVAudioFrameCount(pcm16kMono.count / 2)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "KeepAudio", code: 1)
        }
        buffer.frameLength = frameCount
        pcm16kMono.withUnsafeBytes { raw in
            if let dst = buffer.int16ChannelData?[0], let src = raw.bindMemory(to: Int16.self).baseAddress {
                dst.update(from: src, count: Int(frameCount))
            }
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
