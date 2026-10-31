import Foundation

/// Debug PCM inject helpers: decode base64 / file → 16 kHz mono Int16 LE.
/// Used by Agent IO `inject_pcm` and unit tests. Not a user-facing keep-audio path.
enum PCMInject {
    static let preferredSampleRate = 16_000
    /// Hard cap for one inject (~30s @16k Int16) — matches VAD max utterance.
    static let maxBytes16k = preferredSampleRate * 2 * 30
    /// Trailing silence so VAD can silence-end and leave the utt outside the 1s pending window.
    static let defaultPadSilenceMs = 2_000

    struct ResolvedPCM: Equatable {
        var data16kMono: Data
        var sourceSampleRate: Int
        var sourceBytes: Int
        var durationMs: Int
        var source: String
    }

    /// Resolve `pcm_base64` **or** `path` into 16 kHz mono Int16 LE.
    static func resolve(
        pcmBase64: String?,
        path: String?,
        sampleRate: Int?
    ) throws -> ResolvedPCM {
        let sr = sampleRate ?? preferredSampleRate
        guard sr == 16_000 || sr == 48_000 else {
            throw AgentIOError.invalidArgument("sample_rate must be 16000 or 48000 (got \(sr))")
        }

        let raw: Data
        let source: String
        if let path, !path.isEmpty {
            if let b64 = pcmBase64, !b64.isEmpty {
                throw AgentIOError.invalidArgument("provide either path or pcm_base64, not both")
            }
            let url = try allowedFileURL(path)
            raw = try Data(contentsOf: url)
            source = "path:\(url.path)"
        } else if let b64 = pcmBase64, !b64.isEmpty {
            guard let decoded = Data(base64Encoded: b64, options: [.ignoreUnknownCharacters]) else {
                throw AgentIOError.invalidArgument("pcm_base64 is not valid base64")
            }
            raw = decoded
            source = "pcm_base64"
        } else {
            throw AgentIOError.invalidArgument("inject_pcm requires path or pcm_base64")
        }

        guard !raw.isEmpty else {
            throw AgentIOError.invalidArgument("PCM payload is empty")
        }
        let even = raw.count - (raw.count % 2)
        guard even > 0 else {
            throw AgentIOError.invalidArgument("PCM payload too short")
        }
        var pcm = raw.prefix(even)
        if sr == 48_000 {
            pcm = Data(downsample48kTo16k(Int16LE: Data(pcm)))
        }
        if pcm.count > maxBytes16k {
            throw AgentIOError.invalidArgument(
                "PCM too long after convert (\(pcm.count) bytes); max \(maxBytes16k) (~30s @16k)"
            )
        }
        let durationMs = pcm.count / 2 * 1000 / preferredSampleRate
        return ResolvedPCM(
            data16kMono: Data(pcm),
            sourceSampleRate: sr,
            sourceBytes: even,
            durationMs: durationMs,
            source: source
        )
    }

    /// Pad trailing digital silence (default 2s) so VAD can close the utterance.
    static func withTrailingSilence(_ pcm: Data, silenceMs: Int = defaultPadSilenceMs) -> Data {
        let samples = max(0, preferredSampleRate * silenceMs / 1000)
        guard samples > 0 else { return pcm }
        var out = pcm
        out.append(Data(count: samples * 2))
        return out
    }

    /// Energy-only synthetic clip for **VAD unit tests** (not for YAMNet/ASR).
    /// Formant buzz is labeled `music` by YAMNet — use `docs/fixtures/speech_zh_16k_mono.pcm` for gate/ASR.
    static func makeSyntheticSpeechFixture(
        speechSeconds: Double = 4.0,
        silenceSeconds: Double = 2.0,
        sampleRate: Int = 16_000
    ) -> Data {
        let nSpeech = Int(Double(sampleRate) * speechSeconds)
        let nSil = Int(Double(sampleRate) * silenceSeconds)
        var out = Data(count: (nSpeech + nSil) * 2)
        out.withUnsafeMutableBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            for i in 0..<nSpeech {
                let t = Double(i) / Double(sampleRate)
                let f0 = 110.0 + 30.0 * (t / speechSeconds)
                let syl = 0.55 + 0.45 * abs(sin(2 * Double.pi * 3.7 * t))
                let attack = min(1.0, t / 0.04)
                let release = min(1.0, (speechSeconds - t) / 0.08)
                let env = syl * attack * release
                let phase = 2 * Double.pi * f0 * t
                let buzz = sin(phase) + 0.45 * sin(2 * phase) + 0.25 * sin(3 * phase)
                let f1 = sin(2 * Double.pi * 700 * t) * 0.35
                let f2 = sin(2 * Double.pi * 1220 * t) * 0.22
                let f3 = sin(2 * Double.pi * 2600 * t) * 0.10
                let noise = Double((i &* 1_103_515_245 &+ 12_345) & 0x7fff_ffff) / Double(0x7fff_ffff) - 0.5
                let x = (0.55 * buzz + f1 + f2 + f3 + 0.04 * noise) * env
                let clamped = max(-1.0, min(1.0, x * 0.55))
                samples[i] = Int16(clamped * 20_000.0)
            }
            // Trailing silence already zero-initialized.
            _ = nSil
        }
        return out
    }

    // MARK: - Path allowlist (no arbitrary filesystem read)

    static func allowedFileURL(_ path: String) throws -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        let pathStr = url.path
        guard FileManager.default.fileExists(atPath: pathStr) else {
            throw AgentIOError.notFound("PCM file not found: \(pathStr)")
        }

        let allowedPrefixes: [String] = {
            var roots = [
                AppPaths.recordsRoot.standardizedFileURL.path,
                AppPaths.scratchDirectory.standardizedFileURL.path,
            ]
            // Checked-in fixtures (repo checkout or sibling relative paths).
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            roots.append(cwd.appendingPathComponent("docs/fixtures").path)
            roots.append(cwd.appendingPathComponent("Tests/Fixtures").path)
            if let res = Bundle.main.resourceURL {
                roots.append(res.appendingPathComponent("fixtures").path)
            }
            return roots.map { ($0 as NSString).standardizingPath }
        }()

        let standardized = (pathStr as NSString).standardizingPath
        let ok = allowedPrefixes.contains { prefix in
            standardized == prefix || standardized.hasPrefix(prefix + "/")
        }
        // Also allow any path that ends under …/docs/fixtures/ or …/Tests/Fixtures/
        let fixtureHint =
            standardized.contains("/docs/fixtures/")
            || standardized.contains("/Tests/Fixtures/")
            || standardized.hasSuffix("/docs/fixtures")
            || standardized.hasSuffix("/Tests/Fixtures")
        guard ok || fixtureHint else {
            throw AgentIOError.invalidArgument(
                "path must be under records root, scratch/, docs/fixtures/, or Tests/Fixtures/"
            )
        }
        return url
    }

    /// Cheap 48 kHz → 16 kHz: keep every 3rd Int16 sample (agent fixtures / SCK rate).
    static func downsample48kTo16k(Int16LE data: Data) -> Data {
        let n = data.count / 2
        guard n > 0 else { return Data() }
        let outCount = n / 3
        var out = Data(count: outCount * 2)
        data.withUnsafeBytes { srcRaw in
            let src = srcRaw.bindMemory(to: Int16.self)
            out.withUnsafeMutableBytes { dstRaw in
                let dst = dstRaw.bindMemory(to: Int16.self)
                var j = 0
                var i = 0
                while i + 2 < n && j < outCount {
                    dst[j] = src[i]
                    j += 1
                    i += 3
                }
            }
        }
        return out
    }
}
