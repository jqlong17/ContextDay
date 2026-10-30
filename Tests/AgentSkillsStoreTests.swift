import XCTest
@testable import ContextDay

/// Bundle → App Support seed + Agent IO skills tools (writable copy only).
final class AgentSkillsStoreTests: XCTestCase {
    private var tempRoot: URL!
    private var bundleRoot: URL!
    private var skillsRoot: URL!
    private var service: AgentIOService!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContextDaySkills-\(UUID().uuidString)", isDirectory: true)
        bundleRoot = tempRoot.appendingPathComponent("BundleAgentSkills", isDirectory: true)
        skillsRoot = tempRoot.appendingPathComponent("AppSupportSkills", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: skillsRoot, withIntermediateDirectories: true)

        let ukDetailed = """
        ---
        id: uk-mom-detailed
        title: Detailed MoM
        version: 1.0.0
        category: uk-meeting
        locale: en-GB
        ---

        # Skill: Detailed MoM

        ## Example / Preview
        ```text
        Title: sample
        Decisions
        1. Ship beta
        ```
        """
        let ukBrief = """
        ---
        id: uk-mom-brief
        title: Brief
        version: 1.0.0
        category: uk-meeting
        locale: en-GB
        ---

        # Brief

        ## Example / Preview
        • one liner preview
        """
        let ukWeekly = """
        ---
        id: uk-weekly
        title: Weekly
        version: 1.0.0
        category: uk-meeting
        locale: en-GB
        ---
        # Weekly
        ## Preview
        week progress sample
        """
        let ukMonthly = """
        ---
        id: uk-monthly
        title: Monthly
        version: 1.0.0
        category: uk-meeting
        locale: en-GB
        ---
        # Monthly
        ## Example
        monthly themes sample
        """
        let ukFollowup = """
        ---
        id: uk-followup-email
        title: Follow-up email
        version: 1.0.0
        category: uk-meeting
        locale: en-GB
        ---
        # Follow-up
        ## Example / Preview
        Subject: Follow-up
        """

        let bundled: [String: String] = [
            "README.md": "# bundled README\n",
            "meeting-minutes.md": "# bundled minutes\n",
            "daily-meeting-digest.md": "# bundled digest\n",
            "feishu-minutes-lark-cli.md": "# bundled feishu\n",
            "meeting-notes-weekly-wiki.md": "# bundled wiki\n",
            "uk-mom-detailed.md": ukDetailed,
            "uk-mom-brief.md": ukBrief,
            "uk-weekly.md": ukWeekly,
            "uk-monthly.md": ukMonthly,
            "uk-followup-email.md": ukFollowup,
            "VERSION": "0.4.0\n",
        ]
        for (name, body) in bundled {
            try body.write(to: bundleRoot.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }

        AgentSkillsStore.skillsRootOverride = skillsRoot
        AgentSkillsStore.bundleRootOverride = bundleRoot

        let dbURL = tempRoot.appendingPathComponent("contextday.sqlite")
        let store = try SegmentStore.openIsolated(databaseURL: dbURL)
        service = AgentIOService(store: store)
    }

    override func tearDownWithError() throws {
        service = nil
        AgentSkillsStore.resetTestOverrides()
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    func testSeedCopiesPackagedTemplates() {
        let root = AgentSkillsStore.ensureSeededFromBundle()
        XCTAssertEqual(root.path, skillsRoot.path)
        for name in AgentSkillsStore.packagedTemplateNames {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: skillsRoot.appendingPathComponent(name).path),
                name
            )
        }
        let listed = AgentSkillsStore.listSkills()
        XCTAssertTrue(listed.contains { $0.name == "meeting-minutes.md" && $0.packaged })
        XCTAssertTrue(listed.contains { $0.name == "uk-mom-detailed.md" && $0.packaged })
    }

    func testUKMeetingShelfMetaAndExample() {
        _ = AgentSkillsStore.ensureSeededFromBundle()
        let shelf = AgentSkillsStore.listUKMeetingSkills()
        XCTAssertEqual(shelf.map(\.id), [
            "uk-mom-detailed",
            "uk-mom-brief",
            "uk-weekly",
            "uk-monthly",
            "uk-followup-email",
        ])
        XCTAssertEqual(shelf[0].title, "Detailed MoM")
        XCTAssertEqual(shelf[0].category, "uk-meeting")
        XCTAssertEqual(shelf[0].locale, "en-GB")
        XCTAssertTrue(shelf[0].examplePreview.contains("Ship beta"))
        XCTAssertTrue(shelf[1].examplePreview.contains("one liner"))
        XCTAssertTrue(shelf[2].examplePreview.contains("week progress"))
    }

    func testClipboardSkillPointerIsOneLiner() {
        _ = AgentSkillsStore.ensureSeededFromBundle()
        let index = AgentPromptTemplate.makeClipboardIndex(skillFileName: nil)
        XCTAssertTrue(index.hasPrefix("请阅读 "))
        XCTAssertTrue(index.hasSuffix("README.md"))
        XCTAssertLessThan(index.count, 400)

        let skill = AgentPromptTemplate.makeClipboardIndex(skillFileName: "uk-mom-brief.md")
        XCTAssertTrue(skill.hasPrefix("请阅读 "))
        XCTAssertTrue(skill.contains(skillsRoot.appendingPathComponent("uk-mom-brief.md").path))
        XCTAssertFalse(skill.contains("## Example"))
        XCTAssertLessThan(skill.count, 400)
    }

    func testUpdateWritesAppSupportOnlyNotBundle() throws {
        _ = AgentSkillsStore.ensureSeededFromBundle()
        let path = try AgentSkillsStore.updateSkill(named: "meeting-minutes.md", content: "# edited by assistant\n")
        XCTAssertTrue(path.hasPrefix(skillsRoot.path))
        let appContent = try String(contentsOf: skillsRoot.appendingPathComponent("meeting-minutes.md"), encoding: .utf8)
        XCTAssertEqual(appContent, "# edited by assistant\n")
        let bundleContent = try String(contentsOf: bundleRoot.appendingPathComponent("meeting-minutes.md"), encoding: .utf8)
        XCTAssertEqual(bundleContent, "# bundled minutes\n")
    }

    func testResetRestoresFromBundle() throws {
        _ = AgentSkillsStore.ensureSeededFromBundle()
        _ = try AgentSkillsStore.updateSkill(named: "meeting-minutes.md", content: "# dirty\n")
        let reset = try AgentSkillsStore.resetToBundled(name: "meeting-minutes.md")
        XCTAssertEqual(reset.count, 1)
        let content = try String(contentsOf: skillsRoot.appendingPathComponent("meeting-minutes.md"), encoding: .utf8)
        XCTAssertEqual(content, "# bundled minutes\n")
    }

    func testRejectsPathTraversal() {
        XCTAssertThrowsError(try AgentSkillsStore.readSkill(named: "../etc/passwd"))
        XCTAssertThrowsError(try AgentSkillsStore.updateSkill(named: "evil.txt", content: "x"))
    }

    func testNeverOverwritesLocalOverridesOnSeed() throws {
        let local = "# my private overrides\n"
        try local.write(
            to: skillsRoot.appendingPathComponent(AgentSkillsStore.localOverridesFileName),
            atomically: true,
            encoding: .utf8
        )
        _ = AgentSkillsStore.ensureSeededFromBundle()
        // Force re-seed via version drift
        try "9.9.9".write(to: bundleRoot.appendingPathComponent("VERSION"), atomically: true, encoding: .utf8)
        _ = AgentSkillsStore.ensureSeededFromBundle()
        let kept = try String(
            contentsOf: skillsRoot.appendingPathComponent(AgentSkillsStore.localOverridesFileName),
            encoding: .utf8
        )
        XCTAssertEqual(kept, local)
    }

    func testProtocolSkillsToolsRoundTrip() throws {
        let listData = try AgentIOProtocol.dispatch(tool: "list_agent_skills", arguments: [:], service: service)
        let list = try JSONDecoder().decode(AgentSkillsListDTO.self, from: listData)
        XCTAssertEqual(list.rootPath, skillsRoot.path)
        XCTAssertFalse(list.skills.isEmpty)

        let getData = try AgentIOProtocol.dispatch(
            tool: "get_agent_skill",
            arguments: ["name": "meeting-minutes.md"],
            service: service
        )
        let got = try JSONDecoder().decode(AgentSkillContentDTO.self, from: getData)
        XCTAssertTrue(got.content.contains("bundled minutes"))

        let updateData = try AgentIOProtocol.dispatch(
            tool: "update_agent_skill",
            arguments: ["name": "meeting-minutes.md", "content": "# via io\n"],
            service: service
        )
        let updated = try JSONDecoder().decode(AgentSkillWriteDTO.self, from: updateData)
        XCTAssertTrue(updated.updated)

        let resetData = try AgentIOProtocol.dispatch(
            tool: "reset_agent_skill",
            arguments: ["name": "meeting-minutes.md"],
            service: service
        )
        let reset = try JSONDecoder().decode(AgentSkillResetDTO.self, from: resetData)
        XCTAssertFalse(reset.resetPaths.isEmpty)

        let promptData = try AgentIOProtocol.dispatch(tool: "get_clipboard_prompt", arguments: [:], service: service)
        let prompt = try JSONDecoder().decode(AgentClipboardPromptDTO.self, from: promptData)
        XCTAssertEqual(prompt.kind, "index")
        XCTAssertTrue(prompt.text.hasPrefix("请阅读 "))
        XCTAssertTrue(prompt.text.contains(skillsRoot.appendingPathComponent("README.md").path))
        XCTAssertLessThan(prompt.text.count, 400)
        XCTAssertFalse(prompt.text.contains("docs/agent-skills"))
        XCTAssertFalse(prompt.text.contains("Spec §"))
        XCTAssertFalse(prompt.text.contains("Segment 字段摘要"))
        XCTAssertFalse(prompt.text.contains("/health"))

        let skillPromptData = try AgentIOProtocol.dispatch(
            tool: "get_clipboard_prompt",
            arguments: ["name": "uk-followup-email.md"],
            service: service
        )
        let skillPrompt = try JSONDecoder().decode(AgentClipboardPromptDTO.self, from: skillPromptData)
        XCTAssertEqual(skillPrompt.kind, "skill")
        XCTAssertTrue(skillPrompt.text.contains("uk-followup-email.md"))
        XCTAssertFalse(skillPrompt.text.contains("Subject:"))
        XCTAssertLessThan(skillPrompt.text.count, 400)
    }

    func testClipboardIndexUsesAbsoluteAppSupportPaths() {
        let text = AgentPromptTemplate.makeClipboardIndex(
            recordsRoot: URL(fileURLWithPath: "/tmp/ContextDayRecordsTest")
        )
        XCTAssertTrue(text.hasPrefix("请阅读 "))
        XCTAssertTrue(text.contains(skillsRoot.appendingPathComponent("README.md").path))
        XCTAssertFalse(text.contains("docs/agent-skills"))
        XCTAssertFalse(text.contains("Spec §"))
        XCTAssertFalse(text.contains("/health"))
        XCTAssertFalse(text.contains("get_recent"))
    }
}
