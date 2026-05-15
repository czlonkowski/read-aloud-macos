import SwiftUI
import KeyboardShortcuts

@main
struct ReadAloudApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu(state: AppState.shared)
        } label: {
            MenuBarLabel(state: AppState.shared)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environment(AppState.shared)
                .frame(minWidth: 520, minHeight: 380)
        }
    }
}

/// Owns the app's launch-time bootstrap: hotkey bridge, AppState wake-up,
/// Accessibility prompt. Runs on the main actor before any SwiftUI scene
/// content is evaluated, which matters here because `MenuBarExtra(.menu)`
/// doesn't evaluate its content until the menu opens.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let state = AppState.shared
            registerHotkeys(state: state)
            Task { await state.bootstrap() }
            _ = SelectionService.ensureAccessibilityTrust(prompt: true)
            Log.app.notice("ReadAloud launched")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @MainActor
    private func registerHotkeys(state: AppState) {
        KeyboardShortcuts.onKeyDown(for: .readSelection) {
            state.handleReadHotkey()
        }
        KeyboardShortcuts.onKeyDown(for: .stopReading) {
            state.handleStopHotkey()
        }
    }
}
