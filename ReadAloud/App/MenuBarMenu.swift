import SwiftUI

struct MenuBarMenu: View {
    @Bindable var state: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            statusSection
            Divider()
            playbackSection
            Divider()
            Button("Settings…") { openSettings() }
                .keyboardShortcut(",")
            Button("Quit Read Aloud") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if !state.accessibilityTrusted {
            Button("Grant Accessibility Permission…") {
                SelectionService.openAccessibilityPreferences()
            }
        }
        if let last = state.lastRead {
            Text("Last: \(last.language.displayName) · \(last.text.prefix(40))…")
                .lineLimit(1)
        } else {
            Text("Idle").foregroundStyle(.secondary)
        }
        if let error = state.lastError {
            Text(error).foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var playbackSection: some View {
        switch state.playbackState {
        case .speaking, .preparing:
            Button("Pause") { state.pause() }
            Button("Stop") { state.stop() }
        case .paused:
            Button("Resume") { state.resume() }
            Button("Stop") { state.stop() }
        case .idle:
            Button("Read Selection") { state.handleReadHotkey() }
                .keyboardShortcut("r", modifiers: [.option, .command])
        }
    }
}
