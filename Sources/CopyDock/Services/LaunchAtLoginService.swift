import Foundation
import ServiceManagement

protocol LaunchAtLoginControlling {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

final class LaunchAtLoginService: LaunchAtLoginControlling {

    private let service = SMAppService.mainApp

    var isEnabled: Bool {
        switch service.status {
        case .enabled: return true
        default: return false
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }
}
