import AppKit
import Foundation

enum UploadError: LocalizedError {
    case noHostsConfigured
    case noImageOnClipboard
    case imageConversionFailed
    case scpFailed(Int32, String)
    case allHostsFailed([(host: String, message: String)])

    var errorDescription: String? {
        switch self {
        case .noHostsConfigured:
            return "No hosts configured. Open Settings."
        case .noImageOnClipboard:
            return "No image on clipboard."
        case .imageConversionFailed:
            return "Couldn't convert clipboard image to PNG."
        case .scpFailed(let code, let stderr):
            let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "scp failed (exit \(code))" + (msg.isEmpty ? "" : ": \(msg)")
        case .allHostsFailed(let failures):
            let summary = failures.map { "\($0.host): \($0.message)" }.joined(separator: "; ")
            return "All hosts failed — \(summary)"
        }
    }
}

struct UploadResult {
    let path: String
    let succeeded: [String]
    let failed: [(host: String, message: String)]
}

struct Uploader {
    let hosts: [String]
    let remoteDirectory: String

    func upload() async throws -> UploadResult {
        let cleaned = hosts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else {
            throw UploadError.noHostsConfigured
        }
        let pngData = try readClipboardImageAsPNG()
        let tempURL = try writeTempFile(pngData)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let remotePath = joinRemotePath(remoteDirectory, makeFilename())

        var succeeded: [String] = []
        var failed: [(host: String, message: String)] = []

        await withTaskGroup(of: (String, Result<Void, Error>).self) { group in
            for host in cleaned {
                let local = tempURL.path
                group.addTask {
                    do {
                        try await runScp(local: local, host: host, remotePath: remotePath)
                        return (host, .success(()))
                    } catch {
                        return (host, .failure(error))
                    }
                }
            }
            for await (host, result) in group {
                switch result {
                case .success: succeeded.append(host)
                case .failure(let err): failed.append((host, err.localizedDescription))
                }
            }
        }

        guard !succeeded.isEmpty else {
            throw UploadError.allHostsFailed(failed)
        }

        succeeded.sort()
        failed.sort { $0.host < $1.host }
        return UploadResult(path: remotePath, succeeded: succeeded, failed: failed)
    }

    private func readClipboardImageAsPNG() throws -> Data {
        guard let image = NSImage(pasteboard: .general) else {
            throw UploadError.noImageOnClipboard
        }
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw UploadError.imageConversionFailed
        }
        return png
    }

    private func writeTempFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pastie-\(UUID().uuidString).png")
        try data.write(to: url)
        return url
    }

    private func makeFilename() -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd-HHmmss"
        return "pastie-\(fmt.string(from: Date())).png"
    }

    private func joinRemotePath(_ dir: String, _ filename: String) -> String {
        let trimmed = dir.hasSuffix("/") ? String(dir.dropLast()) : dir
        return "\(trimmed)/\(filename)"
    }
}

private func runScp(local: String, host: String, remotePath: String) async throws {
    try await Task.detached(priority: .userInitiated) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
        process.arguments = ["-q", local, "\(host):\(remotePath)"]
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let data = try? stderrPipe.fileHandleForReading.readToEnd()
            let msg = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            throw UploadError.scpFailed(process.terminationStatus, msg)
        }
    }.value
}
