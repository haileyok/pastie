import AppKit
import Foundation
import Observation

struct HostMapping: Codable, Identifiable, Hashable {
    var id = UUID()
    var windowName: String
    var sshHost: String
}

@Observable
final class AppState {
    var mappings: [HostMapping] {
        didSet { persistMappings() }
    }

    var remoteDirectory: String {
        didSet { UserDefaults.standard.set(remoteDirectory, forKey: Keys.remoteDirectory) }
    }

    var status: Status = .idle
    var lastUploadedPath: String?

    enum Status: Equatable {
        case idle
        case uploading
        case success(String)
        case failure(String)
    }

    private enum Keys {
        static let mappings = "hostMappings"
        static let remoteDirectory = "remoteDirectory"
    }

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Keys.mappings),
           let saved = try? JSONDecoder().decode([HostMapping].self, from: data) {
            self.mappings = saved
        } else {
            self.mappings = [
                HostMapping(windowName: "lena-2", sshHost: "coder.lena-2"),
                HostMapping(windowName: "gamma", sshHost: "gamma"),
            ]
        }
        self.remoteDirectory = defaults.string(forKey: Keys.remoteDirectory) ?? "~/uploads"
    }

    func currentWindowName() -> String? {
        let source = "tell application \"ghostty\" to get name of front window"
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if error != nil { return nil }
        guard let value = result.stringValue, !value.isEmpty else { return nil }
        return value
    }

    func resolvedHost() -> String? {
        guard let name = currentWindowName() else { return nil }
        return mappings.first { $0.windowName == name }?.sshHost
    }

    private func persistMappings() {
        if let data = try? JSONEncoder().encode(mappings) {
            UserDefaults.standard.set(data, forKey: Keys.mappings)
        }
    }
}
