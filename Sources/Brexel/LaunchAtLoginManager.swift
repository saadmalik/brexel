import Foundation
import ServiceManagement

struct LaunchAtLoginSnapshot {
    let isEnabled: Bool
    let requiresApproval: Bool
}

struct LaunchAtLoginManager {
    var snapshot: LaunchAtLoginSnapshot {
        switch SMAppService.mainApp.status {
        case .enabled:
            return LaunchAtLoginSnapshot(isEnabled: true, requiresApproval: false)
        case .requiresApproval:
            return LaunchAtLoginSnapshot(isEnabled: true, requiresApproval: true)
        case .notRegistered, .notFound:
            return LaunchAtLoginSnapshot(isEnabled: false, requiresApproval: false)
        @unknown default:
            return LaunchAtLoginSnapshot(isEnabled: false, requiresApproval: false)
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try register()
        } else {
            try unregister()
        }
    }

    private func register() throws {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            return
        case .notRegistered, .notFound:
            try SMAppService.mainApp.register()
        @unknown default:
            try SMAppService.mainApp.register()
        }
    }

    private func unregister() throws {
        switch SMAppService.mainApp.status {
        case .notRegistered, .notFound:
            return
        case .enabled, .requiresApproval:
            try SMAppService.mainApp.unregister()
        @unknown default:
            try SMAppService.mainApp.unregister()
        }
    }
}
