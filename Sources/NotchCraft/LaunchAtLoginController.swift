import Foundation
import ServiceManagement

struct LaunchAtLoginStatus {
    let isAvailable: Bool
    let isEnabled: Bool
    let helperText: String
}

enum LaunchAtLoginController {
    static func currentStatus() -> LaunchAtLoginStatus {
        let bundleStatus = BundleLaunchAtLoginProvider.currentStatus()
        let launchAgentStatus = LaunchAgentLaunchAtLoginProvider.currentStatus()

        if bundleStatus?.isEnabled == true {
            return bundleStatus ?? launchAgentStatus
        }

        if launchAgentStatus.isEnabled {
            return launchAgentStatus
        }

        if let bundleStatus, bundleStatus.isAvailable {
            return bundleStatus
        }

        return launchAgentStatus
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        if enabled {
            if let status = try BundleLaunchAtLoginProvider.setEnabledIfAvailable(true) {
                return status
            }

            try LaunchAgentLaunchAtLoginProvider.setEnabled(true)
        } else {
            _ = try? BundleLaunchAtLoginProvider.setEnabledIfAvailable(false)
            try? LaunchAgentLaunchAtLoginProvider.setEnabled(false)
        }

        return currentStatus()
    }
}

private enum BundleLaunchAtLoginProvider {
    static func currentStatus() -> LaunchAtLoginStatus? {
        guard isSupported else { return nil }

        let service = SMAppService.mainApp
        switch service.status {
        case .enabled:
            return LaunchAtLoginStatus(
                isAvailable: true,
                isEnabled: true,
                helperText: "NotchCraft will reopen automatically when you sign in."
            )
        case .requiresApproval:
            return LaunchAtLoginStatus(
                isAvailable: true,
                isEnabled: false,
                helperText: "Approve NotchCraft in System Settings > Login Items to finish enabling startup."
            )
        case .notRegistered:
            return LaunchAtLoginStatus(
                isAvailable: true,
                isEnabled: false,
                helperText: "Turn this on to reopen NotchCraft whenever your Mac starts."
            )
        case .notFound:
            return nil
        @unknown default:
            return LaunchAtLoginStatus(
                isAvailable: false,
                isEnabled: false,
                helperText: "Startup launch is unavailable right now."
            )
        }
    }

    static func setEnabledIfAvailable(_ enabled: Bool) throws -> LaunchAtLoginStatus? {
        guard isSupported else { return nil }

        let service = SMAppService.mainApp
        if enabled {
            if service.status != .enabled {
                try service.register()
            }
        } else if service.status == .enabled || service.status == .requiresApproval {
            try service.unregister()
        }

        return currentStatus()
    }

    private static var isSupported: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }
}

private enum LaunchAgentLaunchAtLoginProvider {
    static func currentStatus() -> LaunchAtLoginStatus {
        guard let executableURL else {
            return LaunchAtLoginStatus(
                isAvailable: false,
                isEnabled: false,
                helperText: "Startup launch is unavailable because this build path could not be resolved."
            )
        }

        guard let definition = currentDefinition() else {
            return LaunchAtLoginStatus(
                isAvailable: true,
                isEnabled: false,
                helperText: "Turn this on to reopen NotchCraft whenever your Mac starts."
            )
        }

        if definition.programPath == executableURL.path {
            return LaunchAtLoginStatus(
                isAvailable: true,
                isEnabled: true,
                helperText: "NotchCraft will relaunch from this build whenever you sign in."
            )
        }

        return LaunchAtLoginStatus(
            isAvailable: true,
            isEnabled: false,
            helperText: "Startup launch points to an older build. Toggle it off and on once to refresh it."
        )
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard let executableURL else {
            throw LaunchAtLoginError.missingExecutable
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)

        if enabled {
            let plist = makePropertyList(executableURL: executableURL)
            let plistData = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )
            try plistData.write(to: launchAgentURL, options: .atomic)
        } else if fileManager.fileExists(atPath: launchAgentURL.path) {
            try fileManager.removeItem(at: launchAgentURL)
        }
    }

    private static func makePropertyList(executableURL: URL) -> [String: Any] {
        [
            "Label": agentLabel,
            "ProgramArguments": [executableURL.path],
            "RunAtLoad": true,
            "KeepAlive": false,
            "WorkingDirectory": executableURL.deletingLastPathComponent().path,
            "ProcessType": "Interactive"
        ]
    }

    private static func currentDefinition() -> LaunchAgentDefinition? {
        guard
            let data = try? Data(contentsOf: launchAgentURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let dictionary = plist as? [String: Any]
        else {
            return nil
        }

        let programArguments = dictionary["ProgramArguments"] as? [String] ?? []
        let programPath = programArguments.first
        return LaunchAgentDefinition(programPath: programPath)
    }

    private static var executableURL: URL? {
        if let processPath = ProcessInfo.processInfo.arguments.first, !processPath.isEmpty {
            return URL(fileURLWithPath: processPath).standardizedFileURL
        }

        return Bundle.main.executableURL?.standardizedFileURL
    }

    private static var launchAgentsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
    }

    private static var launchAgentURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(agentLabel).plist")
    }

    private static var agentLabel: String {
        if let bundleIdentifier = Bundle.main.bundleIdentifier, !bundleIdentifier.isEmpty {
            return "\(bundleIdentifier).startup"
        }

        return "com.notchcraft.startup"
    }
}

private struct LaunchAgentDefinition {
    let programPath: String?
}

private enum LaunchAtLoginError: Error {
    case missingExecutable
}
