import AppKit

/// ContextDay entry point (Phase 0 skeleton).
/// Bundle ID: `app.contextday` — see Spec §3.4 / §3.1.
@main
enum ContextDayApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
