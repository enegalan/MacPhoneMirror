import Foundation
import ServiceManagement

// SMAppService helper for Login Items.
// Settings toggle must live here (Core) so UI does not import ServiceManagement details.

public enum LaunchAtLogin {
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters the app as a Login Item via `SMAppService`.
    public static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
