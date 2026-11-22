import Foundation
enum AppPermissionState { case notDetermined, authorized, limited(String), denied, restricted, unavailable(String) }
enum PermissionManager {
    nonisolated static func automationState(for bundleIdentifier: String, askUserIfNeeded: Bool) -> AppPermissionState { .authorized }
}
