import Foundation

/// First-run / cold-start onboarding copy + gate (Spec §2.7.6).
/// Pure data — UI lives in `OnboardingBubbleController`.
enum OnboardingFlow {
    /// Intro dialogue segments. Advance with 「下一步」; do not dump all at once.
    static let introSegments: [String] = [
        "主人你好，我是 ContextDay。\n我的职责是在本机持续把环境声音转成带时间戳的文字，尽量做到全天可查。",
        "这些记录只保存在你这台 Mac 上。Grok Bot、Codex、Claude 等智能体可以通过本机 Agent IO 去读，帮你写会议纪要、日记或全日整理。",
        "采集、转写和存储都在本地完成，音频不会像许多云端会议转写软件那样被送到未知服务器。可以放心用。",
    ]

    /// Whether a checklist item blocks capture start.
    enum PermissionRequirement: Equatable, Sendable {
        /// Must be OK before starting mic / system-audio capture.
        case recordingRequired
        /// Shown for discoverability only — never blocks start (e.g. Login Item).
        case informational
    }

    struct PermissionItem: Equatable, Sendable {
        var id: String
        var title: String
        var detail: String
        var requirement: PermissionRequirement
    }

    /// Checklist shown after intro (~3–4 items). Login Item is informational only (v0.3.27).
    static let permissionItems: [PermissionItem] = [
        PermissionItem(
            id: "login_item",
            title: "登录时打开",
            detail: "开机 / 登录后自动起来，少一步手动启动",
            requirement: .informational
        ),
        PermissionItem(
            id: "microphone",
            title: "麦克风",
            detail: "录制环境与对话声音",
            requirement: .recordingRequired
        ),
        PermissionItem(
            id: "screen_recording",
            title: "屏幕录制（系统声）",
            detail: "用 ScreenCaptureKit 采集系统音频，不是偷录画面",
            requirement: .recordingRequired
        ),
        PermissionItem(
            id: "records_folder",
            title: "记录文件夹可写",
            detail: "在本机保存转写与（可选）音频证据",
            requirement: .recordingRequired
        ),
    ]

    /// Pure flags for unit-testable start / reminder decisions (Spec §2.7.6 v0.3.27).
    struct PermissionFlags: Equatable, Sendable {
        var loginItemOK: Bool
        var microphoneOK: Bool
        var screenRecordingOK: Bool
        var recordsFolderOK: Bool

        func isSatisfied(itemID: String) -> Bool {
            switch itemID {
            case "login_item": return loginItemOK
            case "microphone": return microphoneOK
            case "screen_recording": return screenRecordingOK
            case "records_folder": return recordsFolderOK
            default: return false
            }
        }
    }

    static var recordingRequiredItems: [PermissionItem] {
        permissionItems.filter { $0.requirement == .recordingRequired }
    }

    static var informationalItems: [PermissionItem] {
        permissionItems.filter { $0.requirement == .informational }
    }

    /// Recording-required items still missing. Login Item is never included.
    static func missingRecordingRequired(flags: PermissionFlags) -> [PermissionItem] {
        recordingRequiredItems.filter { !flags.isSatisfied(itemID: $0.id) }
    }

    /// True when every recording-required permission is OK. Login Item is ignored.
    static func canStartCapture(flags: PermissionFlags) -> Bool {
        missingRecordingRequired(flags: flags).isEmpty
    }

    // MARK: - Conversational copy (中文 mid-register)

    /// After 「稍后再说」— acknowledge deferral; do not start capture.
    static let deferredSkipMessage =
        "好，那我暂时还不能完成录制；等你再次启用时我们再检查权限"

    /// Orb / menu start while required permissions are still missing.
    static func missingRequiredMessage(missingTitles: [String]) -> String {
        let titles = missingTitles.filter { !$0.isEmpty }
        guard !titles.isEmpty else {
            return "很遗憾，还有权限尚未开通，所以不能完成录制。"
        }
        let joined: String
        switch titles.count {
        case 1:
            joined = titles[0]
        case 2:
            joined = "\(titles[0])和\(titles[1])"
        default:
            let head = titles.dropLast().joined(separator: "、")
            joined = "\(head)和\(titles.last!)"
        }
        return "很遗憾，还有\(joined)尚未开通，所以不能完成录制。"
    }

    /// After required grants succeed and the user intended to start work.
    static let readyToWorkMessage = "那开始工作"

    /// After first-run / grant succeeds — soft return to idle ready (no forced capture).
    static let returnToBackgroundMessage = "我先回到后台"

    /// Body lead-in on the first-run permission checklist page.
    static let permissionsIntroBody =
        "为了做到这件事，需要你授予下面几项权限。点「授予权限」后会依次弹出系统对话框："

    /// Present while first-run onboarding is incomplete (Spec §2.7.6).
    /// `gateReady` is kept for call-site compatibility / logging; it does **not** suppress the
    /// bubble — otherwise launch can skip intro while still needing Login Item / TCC ownership
    /// in the bubble CTA.
    static func shouldPresent(completed: Bool, gateReady: Bool) -> Bool {
        _ = gateReady
        return !completed
    }

    /// Cold start may sync Login Item (and similar preference→system bridges) **only after**
    /// onboarding has been marked completed (Spec §2.7.6 / v0.3.21).
    /// Launch must never auto-fire `SMAppService.register` / TCC prompts while the first-run
    /// flow is incomplete — even if the ready gate is already green. The bubble's 「授予权限」
    /// (or later Settings / first record) owns those requests. `gateReady` is ignored.
    static func mayAutoSyncSystemPreferences(completed: Bool, gateReady: Bool) -> Bool {
        _ = gateReady
        return completed
    }

    static func introSegment(at index: Int) -> String? {
        guard introSegments.indices.contains(index) else { return nil }
        return introSegments[index]
    }

    static var introCount: Int { introSegments.count }
}

/// Persistence for one-shot first-run onboarding (Spec §2.7.6).
enum OnboardingStore {
    static let completedKey = "onboarding_completed_v1"

    static var isCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: completedKey)
    }

    /// Test / debug only.
    static func resetCompletedFlag() {
        UserDefaults.standard.removeObject(forKey: completedKey)
    }
}
