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

        let bundled = [
            "README.md": "# bundled README\n",
            "meeting-minutes.md": "# bundled minutes\n",
            "daily-meeting-digest.md": "# bundled digest\n",
            "feishu-minutes-lark-cli.md": "# bundled feishu\n",
            "meeting-notes-weekly-wiki.md": "# bundled wiki\n",
            "VERSION": "0.3.4\n",
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
        XCTAssertTrue(prompt.text.contains(skillsRoot.path))
        XCTAssertLessThan(prompt.text.count, 600)
        XCTAssertFalse(prompt.text.contains("docs/agent-skills"))
        XCTAssertFalse(prompt.text.contains("Spec §"))
        XCTAssertFalse(prompt.text.contains("Segment 字段摘要"))
    }

    func testClipboardIndexUsesAbsoluteAppSupportPaths() {
        let text = AgentPromptTemplate.makeClipboardIndex(
            recordsRoot: URL(fileURLWithPath: "/tmp/ContextDayRecordsTest")
        )
        XCTAssertTrue(text.contains(skillsRoot.path))
        XCTAssertTrue(text.contains("get_agent_skill") || text.contains("get_recent"))
        XCTAssertFalse(text.contains("docs/agent-skills"))
        XCTAssertFalse(text.contains("Spec §"))
    }
}
