import AppKit

/// ContextDay entry point (Phase 0 skeleton).
/// Bundle ID: `app.contextday` — see Spec §3.4 / §3.1.
@main
enum ContextDayApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Phase 0 bring-up: `.regular` so a Dock icon appears and the orb is easy to find.
        // Spec accessory / menubar-only policy can return later once DesktopControl is stable.
        app.setActivationPolicy(.regular)
        app.run()
    }
}
