import ServiceManagement
import os

/// Manages whether the app launches at login, using the modern `SMAppService`
/// API (macOS 13+) — registers the main app itself as a login item, no separate
/// helper bundle required.
enum LaunchAtLogin {
    private static let log = Logger(subsystem: "io.bransfer.momentum", category: "login")

    /// Whether the app is currently registered to launch at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Enable or disable launch-at-login. Idempotent and safe to call repeatedly.
    static func setEnabled(_ enabled: Bool) {
        do {
            switch (enabled, SMAppService.mainApp.status) {
            case (true, let status) where status != .enabled:
                try SMAppService.mainApp.register()
            case (false, .enabled):
                try SMAppService.mainApp.unregister()
            default:
                break
            }
        } catch {
            log.error("launch-at-login \(enabled ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
