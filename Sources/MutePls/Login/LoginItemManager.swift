import Foundation
import Darwin

final class LoginItemManager {
    private let label = "dev.local.mutepls"
    private let fileManager = FileManager.default

    private var launchAgentsDirectory: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
    }

    private var plistURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(label).plist")
    }

    var isEnabled: Bool {
        fileManager.fileExists(atPath: plistURL.path)
    }

    func enable() throws {
        let appPath = try resolvedAppPath()
        try fileManager.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
        try writePlist(appPath: appPath)
        _ = runLaunchctl(arguments: ["bootout", "gui/\(getuid())", plistURL.path])
        try runLaunchctl(arguments: ["bootstrap", "gui/\(getuid())", plistURL.path]).throwIfFailed(operation: "enable login item")
        NSLog("MutePls: enabled login item at \(plistURL.path)")
    }

    func disable() throws {
        _ = runLaunchctl(arguments: ["bootout", "gui/\(getuid())", plistURL.path])
        if fileManager.fileExists(atPath: plistURL.path) {
            try fileManager.removeItem(at: plistURL)
        }
        NSLog("MutePls: disabled login item")
    }

    private func resolvedAppPath() throws -> String {
        let bundlePath = Bundle.main.bundlePath
        if bundlePath.hasSuffix(".app") {
            return bundlePath
        }

        let installedAppPath = "/Applications/MutePls.app"
        if fileManager.fileExists(atPath: installedAppPath) {
            return installedAppPath
        }

        throw LoginItemError.appBundleRequired
    }

    private func writePlist(appPath: String) throws {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [
                "/usr/bin/open",
                appPath
            ],
            "RunAtLoad": true,
            "KeepAlive": false
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)
    }

    private func runLaunchctl(arguments: [String]) -> LaunchctlResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return LaunchctlResult(exitCode: process.terminationStatus, output: output)
        } catch {
            return LaunchctlResult(exitCode: 1, output: String(describing: error))
        }
    }
}

struct LaunchctlResult {
    let exitCode: Int32
    let output: String

    func throwIfFailed(operation: String) throws {
        guard exitCode == 0 else {
            throw LoginItemError.launchctlFailed(operation, output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

enum LoginItemError: LocalizedError, CustomStringConvertible {
    case appBundleRequired
    case launchctlFailed(String, String)

    var description: String {
        switch self {
        case .appBundleRequired:
            return "Start at Login requires MutePls to run from MutePls.app. Install it into /Applications first."
        case let .launchctlFailed(operation, output):
            return "Could not \(operation). \(output)"
        }
    }

    var errorDescription: String? {
        description
    }
}
