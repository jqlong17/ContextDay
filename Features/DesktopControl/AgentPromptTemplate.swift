import Foundation

/// Clipboard prompt for Grok Bot–class assistants (Spec §2.8).
enum AgentPromptTemplate {
    /// Fills absolute paths from the current records root into the §2.8 template.
    /// Call sites should pass `AppPaths.recordsRoot` so clipboard paths follow folder changes.
    static func makePrompt(recordsRoot: URL = AppPaths.recordsRoot) -> String {
        let root = recordsRoot.path
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

        建议做法：用只读方式打开 SQLite（如 `sqlite3` 查询），按 t0_ms 时间范围检索 text；若需核对语音，再按 audio_path 拼绝对路径播放。不要假设存在每日转写 .txt。不要修改表结构或删除行，除非用户在对话中明确要求并再次确认。
        """
    }
}
