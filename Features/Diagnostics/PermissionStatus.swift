import AVFoundation
import CoreGraphics
import Foundation

/// TCC / capture permission snapshot. Uses Apple APIs only — never invents grants.
enum PermissionKind: String, Codable, CaseIterable, Sendable {
    case microphone
    case screenRecording = "screen_recording"
    case accessibility
    case automation
}

enum PermissionState: String, Codable, Sendable {
    case authorized
    case denied
    case restricted
    case notDetermined = "not_determined"
    /// Feature not used by MVP; reported for completeness, not a fake grant.
    case notApplicable = "not_applicable"
}

struct PermissionEntry: Codable, Equatable, Sendable {
    var kind: PermissionKind
    var state: PermissionState
    /// Human-readable reason for triage / Console search.
    var reason: String
}

struct PermissionSnapshot: Codable, Equatable, Sendable {
    var checkedAtMs: Int64
    var entries: [PermissionEntry]

    func entry(_ kind: PermissionKind) -> PermissionEntry? {
        entries.first { $0.kind == kind }
    }
}

enum PermissionStatus {
    /// Probe current states without prompting.
    static func snapshot() -> PermissionSnapshot {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return PermissionSnapshot(
            checkedAtMs: now,
            entries: [
                microphoneEntry(),
                screenRecordingEntry(),
                accessibilityEntry(),
                automationEntry(),
            ]
        )
    }

    /// Log once per call site (`launch` / `settings` / `capture_fail`). Searchable via `[permission]`.
    static func logSnapshot(reason: String) {
        let snap = snapshot()
        let summary = snap.entries
            .map { "\($0.kind.rawValue)=\($0.state.rawValue)" }
            .joined(separator: " ")
        AppLog.info(.permission, "snapshot reason=\(reason) \(summary)")
        for entry in snap.entries where entry.state != .authorized && entry.state != .notApplicable {
            AppLog.info(.permission, "\(entry.kind.rawValue) \(entry.state.rawValue) — \(entry.reason)")
        }
    }

    // MARK: - Probes

    private static func microphoneEntry() -> PermissionEntry {
        if #available(macOS 14.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                return PermissionEntry(
                    kind: .microphone, state: .authorized,
                    reason: "AVAudioApplication.recordPermission == granted"
                )
            case .denied:
                return PermissionEntry(
                    kind: .microphone, state: .denied,
                    reason: "Microphone denied — enable in System Settings → Privacy & Security → Microphone"
                )
            case .undetermined:
                return PermissionEntry(
                    kind: .microphone, state: .notDetermined,
                    reason: "Microphone not determined — will prompt on first record"
                )
            @unknown default:
                return PermissionEntry(
                    kind: .microphone, state: .notDetermined,
                    reason: "Unknown AVAudioApplication.recordPermission raw value"
                )
            }
        } else {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                return PermissionEntry(
                    kind: .microphone, state: .authorized,
                    reason: "AVCaptureDevice audio authorized"
                )
            case .denied:
                return PermissionEntry(
                    kind: .microphone, state: .denied,
                    reason: "Microphone denied — enable in System Settings"
                )
            case .restricted:
                return PermissionEntry(
                    kind: .microphone, state: .restricted,
                    reason: "Microphone restricted by system policy"
                )
            case .notDetermined:
                return PermissionEntry(
                    kind: .microphone, state: .notDetermined,
                    reason: "Microphone not determined — will prompt on first record"
                )
            @unknown default:
                return PermissionEntry(
                    kind: .microphone, state: .notDetermined,
                    reason: "Unknown AVCaptureDevice.authorizationStatus"
                )
            }
        }
    }

    private static func screenRecordingEntry() -> PermissionEntry {
        // Used for system-audio via ScreenCaptureKit (not frame recording UX).
        let allowed = CGPreflightScreenCaptureAccess()
        if allowed {
            return PermissionEntry(
                kind: .screenRecording, state: .authorized,
                reason: "CGPreflightScreenCaptureAccess() == true (system audio / SCK)"
            )
        }
        // API does not distinguish denied vs never-prompted.
        return PermissionEntry(
            kind: .screenRecording, state: .notDetermined,
            reason: "Screen Recording not authorized yet (or denied) — required for system audio; enable in System Settings → Privacy & Security → Screen Recording"
        )
    }

    private static func accessibilityEntry() -> PermissionEntry {
        // MVP does not call AX APIs; do not treat AXIsProcessTrusted as a grant we need.
        PermissionEntry(
            kind: .accessibility,
            state: .notApplicable,
            reason: "MVP does not use Accessibility (AX) APIs"
        )
    }

    private static func automationEntry() -> PermissionEntry {
        // Finder open uses NSWorkspace; no Apple Events automation for other apps.
        PermissionEntry(
            kind: .automation,
            state: .notApplicable,
            reason: "MVP does not send Apple Events to other apps (NSWorkspace.open only)"
        )
    }
}
