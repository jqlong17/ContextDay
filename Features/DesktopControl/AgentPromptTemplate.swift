import Foundation

/// Spec §2.8 — clipboard gets a short index; full brief is in-app viewer only.
enum AgentPromptTemplate {
    /// Pasteboard + `get_clipboard_prompt`. Never embeds the full proprietary brief.
    static func makeClipboardIndex(recordsRoot: URL = AppPaths.recordsRoot) -> String {
        let skillsRoot = AgentSkillsStore.ensureSeededFromBundle()
        let skills = skillsRoot.path
        let root = recordsRoot.path
        let port = AgentIOHTTPServer.shared.port
        let healthPort = port > 0 ? port : AgentIOPort.preferred()

        return """
        ContextDay 助手索引（只读本机数据；勿删录音/数据库除非用户再次确认）：先确认 http://127.0.0.1:\(healthPort)/health 含 service=ContextDay；再经 Agent IO 调用 get_recent / get_agent_skill / self_check，或直接读取 \(skills)/（如 README.md、meeting-minutes.md）；转写权威 \(root)/db/contextday.sqlite（无每日 txt）。
        """
    }

    /// Full operational brief for the in-app read-only viewer (Settings).
    /// Must not be written to the system pasteboard.
    static func makeFullPrompt(recordsRoot: URL = AppPaths.recordsRoot) -> String {
        let skillsRoot = AgentSkillsStore.ensureSeededFromBundle()
        let root = recordsRoot.path
        let skills = skillsRoot.path
        let port = AgentIOHTTPServer.shared.port
        let healthPort = port > 0 ? port : AgentIOPort.preferred()

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
        说明：get_clipboard_prompt 仅返回短「助手索引」（与右键「复制提示词」相同），不是下方全文。
        长会议：list_activity（分轨）→ list_speech_blocks → 每块 get_window；勿调用 summarize_window。段 DTO 含派生 t0_iso/t1_iso（权威仍为 t0_ms/t1_ms）。

        助手技能模版（本机可发现绝对路径；由 App Bundle 播种到 Application Support，可经 Agent IO 更新）：
        \(skills)/README.md
        \(skills)/meeting-minutes.md
        \(skills)/daily-meeting-digest.md
        \(skills)/feishu-minutes-lark-cli.md
        \(skills)/meeting-notes-weekly-wiki.md

        建议做法：先 curl /health 确认 service=ContextDay；用 Agent IO 取 Segment 或 Read 上述技能文件；整理纪要遵循技能模版。不要假设存在每日转写 .txt。飞书相关占位符仅用本机私密配置，勿把真实 chat_id 写入仓库或公开回复。
        """
    }
}
