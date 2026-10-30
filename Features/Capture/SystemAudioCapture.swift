import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

/// ScreenCaptureKit system-audio tap → 16 kHz mono Int16 callbacks (Spec dual-rail).
@available(macOS 13.0, *)
final class SystemAudioCapture: NSObject, SCStreamDelegate, SCStreamOutput {
    private var stream: SCStream?
    private var converter: AVAudioConverter?
    private let targetSampleRate: Double = 16_000
    var onPCM: ((Data) -> Void)?
    var onError: ((String) -> Void)?

    func start() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else {
                onError?("No display for system audio capture")
                return
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 48_000
            config.channelCount = 2
            // Minimal video to satisfy SCK; we only consume audio.
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            let audioQueue = DispatchQueue(label: "app.contextday.sck.audio", qos: .userInitiated)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
            // Best-effort no-op screen output so SCK does not spam
            // "stream output NOT found. Dropping frame". Must not block mic or audio.
            // System Music must never mute mic (Spec §1.4 dual-rail).
            do {
                let videoQueue = DispatchQueue(label: "app.contextday.sck.video", qos: .utility)
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
            } catch {
                AppLog.info(
                    .capture,
                    "system screen output optional failed: \(error.localizedDescription) (audio continues)"
                )
            }
            try await stream.startCapture()
            self.stream = stream
            AppLog.info(.capture, "system audio started")
        } catch {
            let msg = "System audio start failed: \(error.localizedDescription)"
            onError?(msg)
            AppLog.error(.capture, msg)
        }
    }

    func stop() {
        let stream = self.stream
        self.stream = nil
        Task {
            try? await stream?.stopCapture()
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard let pcm = Self.pcmBuffer(from: sampleBuffer) else { return }
        let mono16 = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        )!
        if converter == nil || converter?.inputFormat != pcm.format {
            converter = AVAudioConverter(from: pcm.format, to: mono16)
        }
        guard let converter else { return }
        let ratio = mono16.sampleRate / pcm.format.sampleRate
        let capacity = AVAudioFrameCount(Double(pcm.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: mono16, frameCapacity: capacity) else { return }
        var error: NSError?
        var consumed = false
        _ = converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return pcm
        }
        guard out.frameLength > 0, let ch = out.int16ChannelData else { return }
        let data = Data(bytes: ch[0], count: Int(out.frameLength) * MemoryLayout<Int16>.size)
        onPCM?(data)
    }

    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return nil
        }
        var asbd = asbdPtr.pointee
        guard let format = AVAudioFormat(streamDescription: &asbd) else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer) == noErr,
              let dataPointer else { return nil }
        if let dst = buffer.floatChannelData?[0] {
            memcpy(dst, dataPointer, min(length, Int(frames) * MemoryLayout<Float>.size * Int(format.channelCount)))
        } else if let dst = buffer.int16ChannelData?[0] {
            memcpy(dst, dataPointer, min(length, Int(frames) * MemoryLayout<Int16>.size * Int(format.channelCount)))
        } else {
            return nil
        }
        return buffer
    }
}
