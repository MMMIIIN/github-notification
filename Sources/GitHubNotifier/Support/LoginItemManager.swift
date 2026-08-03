import Foundation
import ServiceManagement

/// Wraps `SMAppService` to toggle "launch at login" for the menu bar app.
enum LoginItemManager {
    /// Reflects the current registration state.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters the app as a login item.
    /// Returns true on success. Fails silently-ish (returns false) when run from
    /// an unregistered location (e.g. a raw binary rather than an .app bundle).
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            NSLog("LoginItemManager: failed to set launch-at-login: \(error.localizedDescription)")
            return false
        }
    }

    /// Reconciles the SMAppService registration with the stored preference.
    static func sync(to desired: Bool) {
        guard isEnabled != desired else { return }
        setEnabled(desired)
    }
}
