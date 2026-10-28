import AppKit

/// Application lifecycle: data dirs, DesktopControl orb, Agent IO HTTP (:8787).
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var desktopControl: DesktopControlController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try SegmentStore.shared.prepareApplicationSupport()
        } catch {
            NSLog("ContextDay: failed to prepare Application Support: \(error)")
        }

        AgentIOHTTPServer.shared.start(port: 8787)

        let controller = DesktopControlController()
        controller.show()
        desktopControl = controller
    }

    func applicationWillTerminate(_ notification: Notification) {
        AgentIOHTTPServer.shared.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Accessory app: keep running with the orb; no document windows.
        false
    }
}
