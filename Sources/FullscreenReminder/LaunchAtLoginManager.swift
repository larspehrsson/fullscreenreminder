import Foundation

enum LaunchAtLoginManager {
    static func setEnabled(_ enabled: Bool) throws {
        let fileManager = FileManager.default
        let agentURL = launchAgentURL
        let directoryURL = agentURL.deletingLastPathComponent()

        if enabled {
            if !fileManager.fileExists(atPath: directoryURL.path) {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            }

            let executablePath = URL(fileURLWithPath: CommandLine.arguments[0]).standardized.path
            let plist: [String: Any] = [
                "Label": launchAgentIdentifier,
                "ProgramArguments": [executablePath],
                "RunAtLoad": true,
                "KeepAlive": false,
                "ProcessType": "Background"
            ]

            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: agentURL, options: .atomic)
        } else if fileManager.fileExists(atPath: agentURL.path) {
            try fileManager.removeItem(at: agentURL)
        }
    }

    static func isEnabled() -> Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    private static var launchAgentURL: URL {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        return homeDirectory.appending(path: "Library/LaunchAgents/\(launchAgentIdentifier).plist")
    }

    private static var launchAgentIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.fullscreenreminder.app"
    }
}
