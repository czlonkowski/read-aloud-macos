import Foundation
import AppKit
import ApplicationServices
import SelectedTextKit

struct CapturedSelection: Equatable {
    let text: String
    let sourceBundleID: String?
    let sourceAppName: String?
}

@MainActor
enum SelectionService {
    /// Returns the currently-selected text from the frontmost app.
    /// Uses an ordered fallback chain: accessibility → AppleScript (browsers) → menu Copy → ⌘C synthesis.
    static func capture() async -> CapturedSelection? {
        let front = NSWorkspace.shared.frontmostApplication
        let bundleID = front?.bundleIdentifier
        let appName = front?.localizedName

        let strategies = strategiesFor(bundleID: bundleID)
        Log.selection.debug("Capturing selection from \(bundleID ?? "unknown", privacy: .public) with strategies \(strategies.map(\.label).joined(separator: ", "), privacy: .public)")

        do {
            if let text = try await SelectedTextManager.shared.getSelectedText(strategies: strategies),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return CapturedSelection(text: text, sourceBundleID: bundleID, sourceAppName: appName)
            }
        } catch {
            Log.selection.error("Selection capture failed: \(error.localizedDescription, privacy: .public)")
        }
        return nil
    }

    /// Prompts for Accessibility permission. Call once at launch.
    @discardableResult
    static func ensureAccessibilityTrust(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options: NSDictionary = [key: prompt]
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Opens the System Settings Accessibility pane.
    static func openAccessibilityPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Opens the System Settings Input Monitoring pane (needed for the ⌘C fallback).
    static func openInputMonitoringPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func strategiesFor(bundleID: String?) -> [TextStrategy] {
        let id = (bundleID ?? "").lowercased()
        let isBrowser = id.contains("safari") || id.contains("chrome") || id.contains("firefox") || id.contains("arc")
        if isBrowser {
            return [.appleScript, .accessibility, .menuAction, .shortcut]
        }
        return [.accessibility, .menuAction, .shortcut]
    }
}

private extension TextStrategy {
    var label: String {
        switch self {
        case .auto:          "auto"
        case .accessibility: "accessibility"
        case .appleScript:   "appleScript"
        case .menuAction:    "menuAction"
        case .shortcut:      "shortcut"
        @unknown default:    "unknown"
        }
    }
}
