import Foundation

/// Packaged agent-skill templates: Bundle → `~/Library/Application Support/ContextDay/agent-skills/`.
/// Canonical sources also live in repo `docs/agent-skills/` (SSOT for git); runtime uses App Support.
enum AgentSkillsStore {
    static let appSupportFolderName = "ContextDay"
    static let skillsFolderName = "agent-skills"
    static let versionFileName = "VERSION"
    static let seededStampName = ".seeded-from-version"
    static let localOverridesFileName = "agent-skills.local.md"

    /// Packaged template basenames (never includes local overrides).
    static let packagedTemplateNames: [String] = [
        "README.md",
        "meeting-minutes.md",
        "daily-meeting-digest.md",
        "feishu-minutes-lark-cli.md",
        "meeting-notes-weekly-wiki.md",
        "VERSION",
    ]

    /// XCTest only — redirect writable root away from the user's Application Support.
    static var skillsRootOverride: URL?
    /// XCTest only — fake Bundle `AgentSkills/` directory.
    static var bundleRootOverride: URL?

    /// Writable discoverable root: `~/Library/Application Support/ContextDay/agent-skills/`.
    static var applicationSupportSkillsRoot: URL {
        if let skillsRootOverride { return skillsRootOverride }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent(appSupportFolderName, isDirectory: true)
            .appendingPathComponent(skillsFolderName, isDirectory: true)
    }

    static var absoluteSkillsRootPath: String {
        applicationSupportSkillsRoot.path
    }

    // MARK: - Seed

    /// Copy/refresh packaged templates from Bundle when missing or Bundle VERSION is newer.
    /// Never overwrites `agent-skills.local.md`.
    @discardableResult
    static func ensureSeededFromBundle() -> URL {
        let fm = FileManager.default
        let destRoot = applicationSupportSkillsRoot
        do {
            try fm.createDirectory(at: destRoot, withIntermediateDirectories: true)
        } catch {
            NSLog("ContextDay AgentSkills: mkdir failed \(error.localizedDescription)")
            return destRoot
        }

        guard let bundleRoot = bundleSkillsRoot() else {
            NSLog("ContextDay AgentSkills: Bundle AgentSkills/ missing — skip seed")
            return destRoot
        }

        let bundleVersion = (try? String(contentsOf: bundleRoot.appendingPathComponent(versionFileName), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stampURL = destRoot.appendingPathComponent(seededStampName)
        let seededVersion = (try? String(contentsOf: stampURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let missingPackaged = packagedTemplateNames.contains {
            !fm.fileExists(atPath: destRoot.appendingPathComponent($0).path)
        }
        let versionDrift = (seededVersion ?? "") != bundleVersion
        guard missingPackaged || versionDrift else { return destRoot }

        for name in packagedTemplateNames {
            let src = bundleRoot.appendingPathComponent(name)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = destRoot.appendingPathComponent(name)
            do {
                if fm.fileExists(atPath: dst.path) {
                    try fm.removeItem(at: dst)
                }
                try fm.copyItem(at: src, to: dst)
            } catch {
                NSLog("ContextDay AgentSkills: copy \(name) failed \(error.localizedDescription)")
            }
        }
        try? bundleVersion.write(to: stampURL, atomically: true, encoding: .utf8)
        NSLog("ContextDay AgentSkills: seeded \(destRoot.path) from Bundle version=\(bundleVersion)")
        return destRoot
    }

    static func bundleSkillsRoot() -> URL? {
        if let bundleRootOverride {
            return FileManager.default.fileExists(atPath: bundleRootOverride.path) ? bundleRootOverride : nil
        }
        if let url = Bundle.main.resourceURL?.appendingPathComponent("AgentSkills", isDirectory: true),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return Bundle.main.url(forResource: "AgentSkills", withExtension: nil)
    }

    /// Clear XCTest overrides (call from tearDown).
    static func resetTestOverrides() {
        skillsRootOverride = nil
        bundleRootOverride = nil
    }

    // MARK: - Read / write (App Support only)

    struct SkillFileInfo: Codable, Equatable {
        var name: String
        var path: String
        var bytes: Int
        var packaged: Bool
        var localOverride: Bool
    }

    static func listSkills() -> [SkillFileInfo] {
        ensureSeededFromBundle()
        let root = applicationSupportSkillsRoot
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }
        return names
            .filter { $0.hasSuffix(".md") || $0 == versionFileName }
            .filter { !$0.hasPrefix(".") }
            .sorted()
            .compactMap { name -> SkillFileInfo? in
                let url = root.appendingPathComponent(name)
                guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                      let size = attrs[.size] as? NSNumber else { return nil }
                return SkillFileInfo(
                    name: name,
                    path: url.path,
                    bytes: size.intValue,
                    packaged: packagedTemplateNames.contains(name),
                    localOverride: name == localOverridesFileName
                )
            }
    }

    static func readSkill(named name: String) throws -> (path: String, content: String) {
        ensureSeededFromBundle()
        let safe = try sanitizedFileName(name)
        let url = applicationSupportSkillsRoot.appendingPathComponent(safe)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AgentSkillsError.notFound(safe)
        }
        let content = try String(contentsOf: url, encoding: .utf8)
        return (url.path, content)
    }

    /// Overwrite a skill under App Support only (never Bundle).
    static func updateSkill(named name: String, content: String) throws -> String {
        ensureSeededFromBundle()
        let safe = try sanitizedWritableName(name)
        let url = applicationSupportSkillsRoot.appendingPathComponent(safe)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    /// Reset one packaged template (or all packaged) from Bundle. Skips `agent-skills.local.md`.
    @discardableResult
    static func resetToBundled(name: String?) throws -> [String] {
        guard let bundleRoot = bundleSkillsRoot() else {
            throw AgentSkillsError.bundleMissing
        }
        ensureSeededFromBundle()
        let fm = FileManager.default
        let destRoot = applicationSupportSkillsRoot
        let targets: [String]
        if let name {
            let safe = try sanitizedFileName(name)
            guard packagedTemplateNames.contains(safe), safe != localOverridesFileName else {
                throw AgentSkillsError.notResettable(safe)
            }
            targets = [safe]
        } else {
            targets = packagedTemplateNames
        }
        var reset: [String] = []
        for file in targets {
            let src = bundleRoot.appendingPathComponent(file)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = destRoot.appendingPathComponent(file)
            if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
            try fm.copyItem(at: src, to: dst)
            reset.append(dst.path)
        }
        if let ver = try? String(contentsOf: bundleRoot.appendingPathComponent(versionFileName), encoding: .utf8) {
            try? ver.write(
                to: destRoot.appendingPathComponent(seededStampName),
                atomically: true,
                encoding: .utf8
            )
        }
        return reset
    }

    // MARK: - Name safety

    private static func sanitizedFileName(_ name: String) throws -> String {
        let base = (name as NSString).lastPathComponent
        guard !base.isEmpty, base == name || name.hasSuffix(base),
              !base.contains(".."),
              !base.hasPrefix("."),
              base.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\")) == nil else {
            throw AgentSkillsError.invalidName(name)
        }
        return base
    }

    private static func sanitizedWritableName(_ name: String) throws -> String {
        let base = try sanitizedFileName(name)
        let allowed = Set(packagedTemplateNames.filter { $0.hasSuffix(".md") } + [localOverridesFileName])
        guard allowed.contains(base) else {
            throw AgentSkillsError.notWritable(base)
        }
        return base
    }

    enum AgentSkillsError: Error, LocalizedError {
        case notFound(String)
        case invalidName(String)
        case notWritable(String)
        case notResettable(String)
        case bundleMissing

        var errorDescription: String? {
            switch self {
            case .notFound(let n): return "skill not found: \(n)"
            case .invalidName(let n): return "invalid skill name: \(n)"
            case .notWritable(let n): return "skill not writable via Agent IO: \(n)"
            case .notResettable(let n): return "skill cannot reset from Bundle: \(n)"
            case .bundleMissing: return "Bundle AgentSkills/ missing"
            }
        }
    }
}
