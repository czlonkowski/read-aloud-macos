import SwiftUI

struct SidecarStatusView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Form {
            Section("Local Neural Engine") {
                let enabledBinding = Binding(
                    get: { state.preferences.sidecarEnabled },
                    set: { state.setSidecarEnabled($0) }
                )
                Toggle("Enable neural sidecar", isOn: enabledBinding)

                LabeledContent("Status") {
                    statusBadge
                }

                if case .notInstalled = state.sidecarStatus {
                    Button("Reveal install script in Finder") {
                        revealInstallScript()
                    }
                }
            }

            Section("How it works") {
                Text("The sidecar runs **Kokoro-82M** (English) and **Chatterbox Multilingual** (Polish) locally via MLX/PyTorch. It listens on `127.0.0.1:8000` and streams PCM audio to this app.")
                Text("Install with `scripts/install-sidecar.sh` from the repo. The script uses `uv` to set up a Python environment under `~/Library/Application Support/ReadAloud/sidecar` and registers a launchd agent that starts on demand.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch state.sidecarStatus {
        case .unknown:
            Label("Unknown", systemImage: "questionmark.circle").foregroundStyle(.secondary)
        case .notInstalled:
            Label("Not installed", systemImage: "tray.and.arrow.down").foregroundStyle(.orange)
        case .stopped:
            Label("Installed, stopped", systemImage: "pause.circle").foregroundStyle(.secondary)
        case .starting:
            Label("Starting…", systemImage: "hourglass").foregroundStyle(.blue)
        case .running:
            Label("Running", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }

    private func revealInstallScript() {
        // Best-effort: open the repo's scripts/ folder. Users can also run the
        // script from a terminal — the README has the command.
        if let url = URL(string: "https://github.com/czlonkowski/read-aloud-macos#installing-the-sidecar") {
            NSWorkspace.shared.open(url)
        }
    }
}
