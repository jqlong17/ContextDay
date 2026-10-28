import AppKit

/// Application lifecycle: data dirs, retention, DesktopControl orb, Agent IO HTTP (:18787–18797).
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var desktopControl: DesktopControlController?
    private var sleepObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try SegmentStore.shared.prepareApplicationSupport()
        } catch {
            NSLog("ContextDay: failed to prepare Application Support: \(error)")
        }

        RetentionPurger.purgeIfNeeded()
        if let warning = DiskSpaceGuard.status().warning {
            NSLog("ContextDay Disk: \(warning)")
        }

        let preferredPort = AgentIOPort.preferred()
        DispatchQueue.global(qos: .utility).async {
            // Prefer --port / UserDefaults / Info.plist; scan upward in 18787…18797 if busy.
            AgentIOHTTPServer.shared.start(port: preferredPort)
            let bound = AgentIOHTTPServer.shared.port
            if AgentIOHTTPServer.shared.isListening {
                NSLog(
                    "ContextDay AgentIO HTTP READY 127.0.0.1:\(bound) service=ContextDay "
                        + "(preferred \(preferredPort); override: --port N / defaults \(AgentIOPort.defaultsKey))"
                )
            } else {
                NSLog(
                    "ContextDay AgentIO HTTP NOT LISTENING — preferred \(preferredPort) and fallback range exhausted. "
                        + "Try: defaults write app.contextday \(AgentIOPort.defaultsKey) <free-port>"
                )
            }
        }

        let controller = DesktopControlController()
        controller.show()
        desktopControl = controller

        registerSleepWakeObservers()

        if let seconds = Self.smokeRecordSeconds() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                controller.smokeRecord(forSeconds: seconds)
            }
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
            NSLog("ContextDay: system will sleep — pausing capture (re-start required after wake)")
            self?.desktopControl?.handleSystemSleep()
        }
        let didWake = nc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            NSLog("ContextDay: system woke — capture stays stopped until user starts recording again")
        }
        sleepObservers = [willSleep, didWake]
    }
}
