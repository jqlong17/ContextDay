import AppKit
import Foundation

/// ContextDay entry point. Bundle ID: `app.contextday` (Spec §3.4).
/// GUI: default. MCP stdio: `ContextDay --mcp` (no AppKit run loop).
@main
enum ContextDayApp {
    static func main() {
        if CommandLine.arguments.contains("--mcp") {
            runMCPStdio()
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // `.regular` so a Dock icon appears and the orb is easy to find during bring-up.
        app.setActivationPolicy(.regular)
        app.run()
    }

    private static func runMCPStdio() {
        do {
            try SegmentStore.shared.prepareApplicationSupport()
        } catch {
            let msg = "ContextDay MCP: failed to open store: \(error)\n"
            FileHandle.standardError.write(Data(msg.utf8))
            exit(1)
        }
        AgentIOMCPStdio.run()
    }
}
