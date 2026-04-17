import Foundation
import Observation

@Observable
final class AppState {
    var sshHost: String {
        didSet { UserDefaults.standard.set(sshHost, forKey: Keys.sshHost) }
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
        static let sshHost = "sshHost"
        static let remoteDirectory = "remoteDirectory"
    }

    init() {
        let defaults = UserDefaults.standard
        self.sshHost = defaults.string(forKey: Keys.sshHost) ?? ""
        self.remoteDirectory = defaults.string(forKey: Keys.remoteDirectory) ?? "~/uploads"
    }
}
