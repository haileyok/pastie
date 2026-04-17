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
    let uploader = Uploader(host: state.sshHost, remoteDirectory: state.remoteDirectory)
    state.status = .uploading
    Task {
        do {
            let path = try await uploader.upload()
            state.status = .success(path)
            state.lastUploadedPath = path
            copyToClipboard(path)
            notify(title: "Uploaded", body: path)
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
            TextField("SSH Host", text: $state.sshHost, prompt: Text("e.g. coder"))
            TextField("Remote Directory", text: $state.remoteDirectory, prompt: Text("e.g. ~/uploads"))
            Text("SSH Host can be any alias from ~/.ssh/config, or user@hostname.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 420)
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
