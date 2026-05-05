import AppKit
import Carbon.HIToolbox
import SwiftUI

@main
struct PastieApp: App {
    @State private var state = AppState()
    @State private var hotkey: Hotkey?

    init() {
        let initialState = AppState()
        _state = State(initialValue: initialState)
        let mods = UInt32(controlKey | optionKey | cmdKey)
        _hotkey = State(initialValue: Hotkey(keyCode: UInt32(kVK_ANSI_V), modifiers: mods) {
            Task { @MainActor in triggerUpload(state: initialState) }
        })
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(state: state)
        } label: {
            Image(systemName: iconName)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(state: state)
        }
    }

    private var iconName: String {
        switch state.status {
        case .idle: return "photo.on.rectangle"
        case .uploading: return "arrow.up.circle"
        case .success: return "checkmark.circle"
        case .failure: return "exclamationmark.triangle"
        }
    }
}

struct MenuContentView: View {
    let state: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        routingView

        Divider()

        Button("Upload Clipboard Image") { upload() }
            .keyboardShortcut("u")

        Divider()

        statusView

        if let path = state.lastUploadedPath {
            Text(path).foregroundStyle(.secondary)
            Button("Copy Last Path") { copyToClipboard(path) }
        }

        Divider()

        Button("Settings…") { openSettings() }
            .keyboardShortcut(",")

        Button("Quit Pastie") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    @ViewBuilder
    private var routingView: some View {
        let win = state.currentWindowName()
        let host = state.resolvedHost()
        let fallback = state.mappings.map(\.sshHost).filter { !$0.isEmpty }
        if let host {
            Text("\(win ?? "?") → \(host)")
        } else if !fallback.isEmpty {
            let label = win ?? "no window"
            Text("\(label) → fallback (\(fallback.count) hosts)")
        } else {
            Text("No hosts configured").foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch state.status {
        case .idle:
            Text("Ready").foregroundStyle(.secondary)
        case .uploading:
            Text("Uploading…").foregroundStyle(.secondary)
        case .success(let path):
            Text("Uploaded → \(path)").foregroundStyle(.secondary)
        case .failure(let msg):
            Text("Error: \(msg)").foregroundStyle(.red)
        }
    }

    private func upload() { triggerUpload(state: state) }
}

@MainActor
func triggerUpload(state: AppState) {
    if case .uploading = state.status { return }

    let resolved = state.resolvedHost()
    let allHosts = state.mappings.map(\.sshHost).filter { !$0.isEmpty }
    let targetHosts: [String] = resolved.map { [$0] } ?? allHosts
    let isFallback = resolved == nil

    guard !targetHosts.isEmpty else {
        let msg = "No hosts configured. Open Settings."
        state.status = .failure(msg)
        notify(title: "Pastie", body: msg)
        Task {
            try? await Task.sleep(for: .seconds(3))
            if case .failure = state.status { state.status = .idle }
        }
        return
    }

    let uploader = Uploader(hosts: targetHosts, remoteDirectory: state.remoteDirectory)
    state.status = .uploading
    Task {
        do {
            let result = try await uploader.upload()
            state.lastUploadedPath = result.path
            copyToClipboard(result.path)

            let total = result.succeeded.count + result.failed.count
            let succeededList = result.succeeded.joined(separator: ", ")
            let prefix: String
            if total == 1 {
                prefix = succeededList
            } else if result.failed.isEmpty {
                prefix = "\(result.succeeded.count) hosts"
            } else {
                prefix = "\(result.succeeded.count)/\(total) hosts"
            }
            state.status = .success("\(prefix) → \(result.path)")

            let title: String = {
                if !result.failed.isEmpty { return "Uploaded (partial)" }
                return isFallback ? "Uploaded (fallback)" : "Uploaded"
            }()
            var body = "\(succeededList): \(result.path)"
            if !result.failed.isEmpty {
                body += " · failed: \(result.failed.map(\.host).joined(separator: ", "))"
            }
            notify(title: title, body: body)
        } catch {
            state.status = .failure(error.localizedDescription)
            notify(title: "Upload failed", body: error.localizedDescription)
        }
        try? await Task.sleep(for: .seconds(3))
        if case .uploading = state.status { return }
        state.status = .idle
    }
}

struct SettingsView: View {
    @Bindable var state: AppState

    var body: some View {
        Form {
            Section("Host Mappings") {
                ForEach($state.mappings) { $mapping in
                    HStack {
                        TextField("Window name", text: $mapping.windowName)
                        Text("→").foregroundStyle(.secondary)
                        TextField("SSH host", text: $mapping.sshHost)
                        Button {
                            state.mappings.removeAll { $0.id == mapping.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button("Add Mapping") {
                    state.mappings.append(HostMapping(windowName: "", sshHost: ""))
                }
            }
            Section("Remote Directory") {
                TextField("Path", text: $state.remoteDirectory, prompt: Text("e.g. ~/uploads"))
            }
            Section {
                Text("Pastie reads the frontmost Ghostty window name and uploads to the matching SSH host. If no mapping matches, it falls back to uploading to every configured host. Window name match is exact.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 500)
    }
}

func copyToClipboard(_ string: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(string, forType: .string)
}

func notify(title: String, body: String) {
    let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
    let escapedBody = body.replacingOccurrences(of: "\"", with: "\\\"")
    let script = "display notification \"\(escapedBody)\" with title \"\(escapedTitle)\""
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.arguments = ["-e", script]
    try? task.run()
}
