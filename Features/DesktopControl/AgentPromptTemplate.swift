import Foundation

/// Spec §2.8 — clipboard gets a one-line pointer; full brief is in-app viewer only.
enum AgentPromptTemplate {
    /// Pasteboard + `get_clipboard_prompt`. Never embeds the full proprietary brief,
    /// health URL, tool lists, or data-root paragraphs — only a single “请阅读 …” line.
    /// - Parameter skillFileName: optional packaged `.md` under agent-skills (e.g. `uk-mom-brief.md`);
    ///   nil → README.md index pointer.
    static func makeClipboardIndex(
        recordsRoot: URL = AppPaths.recordsRoot,
        skillFileName: String? = nil
    ) -> String {
        _ = recordsRoot // signature kept for callers / tests; skills path is App Support.
        let skillsRoot = AgentSkillsStore.ensureSeededFromBundle()
        let target: String
        if let skillFileName, !skillFileName.isEmpty {
            let base = (skillFileName as NSString).lastPathComponent
            target = skillsRoot.appendingPathComponent(base).path
        } else {
            target = skillsRoot.appendingPathComponent("README.md").path
        }
        return "请阅读 \(target)"
    }

    /// Full operational brief for the in-app read-only viewer (Settings).
    /// Must not be written to the system pasteboard.
    static func makeFullPrompt(recordsRoot: URL = AppPaths.recordsRoot) -> String {
        let skillsRoot = AgentSkillsStore.ensureSeededFromBundle()
        let root = recordsRoot.path
        let skills = skillsRoot.path
        let port = AgentIOHTTPServer.shared.port
        let healthPort = port > 0 ? port : AgentIOPort.preferred()
        let ukLines = AgentSkillsStore.ukMeetingShelfFileNames
            .map { "\(skills)/\($0)" }
            .joined(separator: "\n")

        return """
        你正在协助使用 ContextDay（本机 24h 语音上下文采集与转写层）。请只读访问下列本机转写数据，不要删除、移动或清空用户录音/数据库，除非用户在对话中明确要求并再次确认。

        产品一句话：ContextDay 在 macOS 本机持续采集麦克风/可选系统声，经门控与 ASR 后把时间线写入 SQLite；转写权威在数据库，不另写每日 txt。

        数据根目录（记录文件夹）：
        \(root)

        权威数据库：
        \(root)/db/contextday.sqlite

        可选留音（仅当用户开启 keep_audio）：
        \(root)/audio/YYYY-MM-DD/{mic|system}/<segment-uuid>.opus

        Segment 字段摘要：
        id(UUID), track(mic|system), t0_ms/t1_ms(UTC epoch ms), tz_at_capture(IANA?),
        text(转写), gate_label(speech|music|other?), audio_path(相对根路径?),
        source_segment_ids, created_at_ms, merged_at_ms?, merge_gap_ms?,
        asr_model_id?, asr_model_version?

        本机 Agent IO（只读转写 + 可读写助手技能模版；仅 127.0.0.1）：
        http://127.0.0.1:\(healthPort)/health
        期望 JSON 含 "service":"ContextDay"。
        转写工具：POST /v1/tools/{search_segments|get_recent|get_window|list_activity|list_speech_blocks|self_check}
        技能工具：POST /v1/tools/{list_agent_skills|get_agent_skill|update_agent_skill|reset_agent_skill|get_clipboard_prompt}
        调试（仅本机）：POST /v1/tools/inject_pcm — path 或 pcm_base64 → 同环缓冲；见 docs/fixtures + Scripts/pcm-inject-example.sh
        说明：get_clipboard_prompt / 右键「复制提示词」仅返回一行「请阅读 …/agent-skills/README.md」（可选 name 指向某一技能文件），不是下方全文。
        长会议：list_activity（分轨）→ list_speech_blocks → 每块 get_window；勿调用 summarize_window。段 DTO 含派生 t0_iso/t1_iso（权威仍为 t0_ms/t1_ms）。

        助手技能模版（本机可发现绝对路径；由 App Bundle 播种到 Application Support，可经 Agent IO 更新）：
        \(skills)/README.md
        \(skills)/meeting-minutes.md
        \(skills)/daily-meeting-digest.md
        \(skills)/feishu-minutes-lark-cli.md
        \(skills)/meeting-notes-weekly-wiki.md
        \(ukLines)

        建议做法：先 curl /health 确认 service=ContextDay；用 Agent IO 取 Segment 或 Read 上述技能文件；整理纪要遵循技能模版。不要假设存在每日转写 .txt。飞书相关占位符仅用本机私密配置，勿把真实 chat_id 写入仓库或公开回复。UK meeting 导出默认不自动发邮件。
        """
    }
}
