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

    struct PermissionItem: Equatable, Sendable {
        var id: String
        var title: String
        var detail: String
    }

    /// Checklist shown after intro (~3–4 items).
    static let permissionItems: [PermissionItem] = [
        PermissionItem(
            id: "login_item",
            title: "登录时打开",
            detail: "开机 / 登录后自动起来，少一步手动启动"
        ),
        PermissionItem(
            id: "microphone",
            title: "麦克风",
            detail: "录制环境与对话声音"
        ),
        PermissionItem(
            id: "screen_recording",
            title: "屏幕录制（系统声）",
            detail: "用 ScreenCaptureKit 采集系统音频，不是偷录画面"
        ),
        PermissionItem(
            id: "records_folder",
            title: "记录文件夹可写",
            detail: "在本机保存转写与（可选）音频证据"
        ),
    ]

    /// Present when the user has not finished onboarding and the ready gate is not yet green.
    static func shouldPresent(completed: Bool, gateReady: Bool) -> Bool {
        !completed && !gateReady
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
