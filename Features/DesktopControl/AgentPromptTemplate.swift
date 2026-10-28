import Foundation

/// Clipboard prompt for Grok Bot–class assistants (Spec §2.8).
enum AgentPromptTemplate {
    /// Fills absolute paths from the current records root into the §2.8 template.
    /// Also points at repo `docs/agent-skills/` templates and Agent IO HTTP (default :18787).
    static func makePrompt(recordsRoot: URL = AppPaths.recordsRoot) -> String {
        let root = recordsRoot.path
        // Skills live in the ContextDay git checkout (not Application Support). Prefer
        // resolving next to a known checkout; fall back to Spec Mac path + relative hint.
        let skillsRoot = Self.agentSkillsDirectoryPath()
        return """
        你正在协助使用 ContextDay（本机 24h 语音上下文采集与转写层）。请只读访问下列本机数据，不要删除、移动或清空用户文件。

        产品一句话：ContextDay 在 macOS 本机持续采集麦克风/可选系统声，经门控与 ASR 后把时间线写入 SQLite；转写权威在数据库，不另写每日 txt。

        数据根目录（记录文件夹）：
        \(root)

        权威数据库：
        \(root)/db/contextday.sqlite

        可选留音（仅当用户开启 keep_audio；Opus）：
        \(root)/audio/YYYY-MM-DD/{mic|system}/<segment-uuid>.opus

        Segment 字段摘要（详见产品 Spec §3.3）：
        id(UUID), track(mic|system), t0_ms/t1_ms(UTC epoch ms), tz_at_capture(IANA?),
        text(转写), gate_label(speech|music|other?), audio_path(相对根路径?),
        source_segment_ids, created_at_ms, merged_at_ms?, merge_gap_ms?,
        asr_model_id?, asr_model_version?

        本机 Agent IO（只读 HTTP，默认 18787；忙碌时可能为 18788–18797）：
        http://127.0.0.1:18787/health
        期望 JSON 含 "service":"ContextDay"。工具：POST /v1/tools/{search_segments|get_recent|get_window|list_activity}

        助手技能模板（仓库内脱敏 Markdown，只读；无个人飞书 ID）：
        \(skillsRoot)/README.md
        \(skillsRoot)/meeting-minutes.md
        \(skillsRoot)/daily-meeting-digest.md
        \(skillsRoot)/feishu-minutes-lark-cli.md

        建议做法：先 curl /health 确认 service=ContextDay；再用 Agent IO 或 sqlite3 只读按 t0_ms 检索 text；整理纪要时遵循 docs/agent-skills/ 对应模板。不要假设存在每日转写 .txt。不要修改表结构或删除行，除非用户在对话中明确要求并再次确认。飞书投递仅用本机私密占位符，勿把真实 chat_id 写入仓库。
        """
    }

    /// Best-effort absolute path to `docs/agent-skills` in a ContextDay checkout.
    private static func agentSkillsDirectoryPath() -> String {
        let candidates: [URL] = [
            URL(fileURLWithPath: "/Users/ruska/projects/ContextDay/docs/agent-skills", isDirectory: true),
            URL(fileURLWithPath: AppPaths.recordsRoot.path)
                .deletingLastPathComponent()
                .appendingPathComponent("ContextDay/docs/agent-skills", isDirectory: true),
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent("docs/agent-skills", isDirectory: true),
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return url.path
        }
        // Stable relative hint when checkout path is unknown at runtime.
        return "docs/agent-skills"
    }
}
