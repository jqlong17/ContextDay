import AppKit

/// Application lifecycle. Phase 0: ensure data dirs, show DesktopControl orb.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var desktopControl: DesktopControlController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try SegmentStore.shared.prepareApplicationSupport()
        } catch {
            NSLog("ContextDay: failed to prepare Application Support: \(error)")
        }

        let controller = DesktopControlController()
        controller.show()
        desktopControl = controller
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Accessory app: keep running with the orb; no document windows.
        false
    }
}
