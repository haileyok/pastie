import AppKit
import Foundation

enum UploadError: LocalizedError {
    case settingsIncomplete
    case noImageOnClipboard
    case imageConversionFailed
    case scpFailed(Int32, String)

    var errorDescription: String? {
        switch self {
        case .settingsIncomplete:
            return "SSH host is not set. Open Settings."
        case .noImageOnClipboard:
            return "No image on clipboard."
        case .imageConversionFailed:
            return "Couldn't convert clipboard image to PNG."
        case .scpFailed(let code, let stderr):
            let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "scp failed (exit \(code))" + (msg.isEmpty ? "" : ": \(msg)")
        }
    }
}

struct Uploader {
    let host: String
    let remoteDirectory: String

    func upload() async throws -> String {
        guard !host.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw UploadError.settingsIncomplete
        }
        let pngData = try readClipboardImageAsPNG()
        let tempURL = try writeTempFile(pngData)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let remotePath = joinRemotePath(remoteDirectory, makeFilename())
        try await runScp(local: tempURL.path, host: host, remotePath: remotePath)
        return remotePath
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
}
