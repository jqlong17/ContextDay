import Foundation
import ServiceManagement

/// Login Item via `SMAppService.mainApp` (macOS 13+; deployment 14). Spec §2.2 / §2.10.
/// App Store: user must be able to turn this off — Settings checkbox drives register/unregister.
enum LoginItemService {
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static var isEnabled: Bool {
        status == .enabled
    }

    static var statusLabel: String {
        switch status {
        case .enabled: return "enabled"
        case .requiresApproval: return "requires_approval"
        case .notRegistered: return "not_registered"
        case .notFound: return "not_found"
        @unknown default: return "unknown"
        }
    }

    /// Register or unregister the main app as a Login Item. Idempotent.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        let current = status
        do {
            if enabled {
                switch current {
                case .enabled:
                    return true
                case .requiresApproval:
                    AppLog.info(.app, "login item already registered; waiting for System Settings approval")
                    return true
                default:
                    try SMAppService.mainApp.register()
                }
            } else {
                switch current {
                case .notRegistered:
                    return true
                case .enabled, .requiresApproval:
                    try SMAppService.mainApp.unregister()
                default:
                    try SMAppService.mainApp.unregister()
                }
            }
            AppLog.info(.app, "login item setEnabled=\(enabled) → \(statusLabel)")
            return true
        } catch {
            AppLog.error(
                .app,
                "login item setEnabled=\(enabled) failed status=\(statusLabel): \(error.localizedDescription)"
            )
            return false
        }
    }

    /// Align `SMAppService` with the Settings preference (call on launch + after save).
    static func syncFromPreference(_ openAtLogin: Bool) {
        if openAtLogin {
            if status != .enabled {
                _ = setEnabled(true)
            }
        } else if status == .enabled || status == .requiresApproval {
            _ = setEnabled(false)
        }
    }
}
