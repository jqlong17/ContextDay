import AppKit

/// Application lifecycle: data dirs, retention, DesktopControl orb, Agent IO HTTP (:18787–18797).
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var desktopControl: DesktopControlController?
    private var sleepObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try SegmentStore.shared.prepareApplicationSupport()
        } catch {
            AppLog.error(.store, "failed to prepare records tree: \(error.localizedDescription)")
        }

        PermissionStatus.logSnapshot(reason: "launch")

        // Spec §2.2 / §2.10: Login Item preference → SMAppService (default ON; user can disable).
        LoginItemService.syncFromPreference(AppConfigStore.load().openAtLogin)

        RetentionPurger.purgeIfNeeded()
        if let warning = DiskSpaceGuard.status().warning {
            AppLog.info(.store, "disk: \(warning)")
        }

        let skillsRoot = AgentSkillsStore.ensureSeededFromBundle()
        AppLog.info(.app, "agent-skills root \(skillsRoot.path)")

        let controller = DesktopControlController()
        controller.show()
        desktopControl = controller

        let preferredPort = AgentIOPort.preferred()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            // Prefer --port / UserDefaults / Info.plist; scan upward in 18787…18797 if busy.
            AgentIOHTTPServer.shared.start(port: preferredPort)
            let bound = AgentIOHTTPServer.shared.port
            if AgentIOHTTPServer.shared.isListening {
                AppLog.info(
                    .agentIO,
                    "HTTP READY 127.0.0.1:\(bound) service=ContextDay preferred=\(preferredPort)"
                )
            } else {
                AppLog.error(
                    .agentIO,
                    "HTTP NOT LISTENING — preferred \(preferredPort) and fallback range exhausted"
                )
            }
            // Spec §2.7.4: after Agent IO bind attempt, evaluate ready-blink once (+ one short retry).
            DispatchQueue.main.async {
                self?.scheduleReadyBlink()
            }
        }

        registerSleepWakeObservers()

        if let seconds = Self.smokeRecordSeconds() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                controller.smokeRecord(forSeconds: seconds)
            }
        }
    }

    /// Play ready clip once when mic + screen + records root are OK; at most one per cold start.
    private func scheduleReadyBlink() {
        desktopControl?.considerReadyBlink()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.desktopControl?.considerReadyBlink()
        }
    }

    private static func smokeRecordSeconds() -> TimeInterval? {
        for arg in CommandLine.arguments {
            if arg.hasPrefix("--smoke-record-seconds=") {
                let raw = String(arg.dropFirst("--smoke-record-seconds=".count))
                if let v = Double(raw), v > 0 { return v }
            }
        }
        return nil
    }

    func applicationWillTerminate(_ notification: Notification) {
        for obs in sleepObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        sleepObservers.removeAll()
        desktopControl?.handleSystemSleep()
        AgentIOHTTPServer.shared.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Spec sleep boundary: stop capture on sleep so we never silently resume after wake.
    private func registerSleepWakeObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        let willSleep = nc.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            AppLog.info(.app, "system will sleep — pausing capture (no auto-resume)")
            self?.desktopControl?.handleSystemSleep()
        }
        let didWake = nc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            AppLog.info(.app, "system woke — capture stays stopped until user starts recording")
        }
        sleepObservers = [willSleep, didWake]
    }
}
