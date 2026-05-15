import SwiftUI
import KeyboardShortcuts

@main
struct ReadAloudApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var state = AppState()

    init() {
        // Hotkey handlers are registered on the main actor so they can safely
        // touch AppState. We capture by reference via a private bridge below
        // because `init()` cannot access `_state.wrappedValue.handle…` directly.
        HotkeyBridge.install()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu(state: state)
                .task { await state.bootstrap() }
                .task { HotkeyBridge.connect(to: state) }
        } label: {
            MenuBarLabel(state: state)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environment(state)
                .frame(minWidth: 520, minHeight: 380)
        }
    }
}

/// Keeps the app alive even when no window is open, prompts for Accessibility on first launch.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            _ = SelectionService.ensureAccessibilityTrust(prompt: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

/// Bridges the global hotkey callbacks (registered before AppState exists) to
/// the live `AppState` instance once SwiftUI hands it to us via `.task`.
@MainActor
enum HotkeyBridge {
    private static var weakState: WeakBox<AppState> = WeakBox()
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        KeyboardShortcuts.onKeyDown(for: .readSelection) {
            Self.weakState.value?.handleReadHotkey()
        }
        KeyboardShortcuts.onKeyDown(for: .stopReading) {
            Self.weakState.value?.handleStopHotkey()
        }
    }

    static func connect(to state: AppState) {
        weakState.value = state
    }
}

/// Tiny weak wrapper so HotkeyBridge can hold AppState without retaining it.
@MainActor
final class WeakBox<T: AnyObject> {
    weak var value: T?
    init() {}
}
