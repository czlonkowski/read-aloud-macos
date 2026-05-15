import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        TabView {
            HotkeyTab()
                .tabItem { Label("Hotkey", systemImage: "command") }

            VoicesTab()
                .tabItem { Label("Voices", systemImage: "speaker.wave.2") }

            SidecarTab()
                .tabItem { Label("Neural", systemImage: "cpu") }

            PronunciationTab()
                .tabItem { Label("Pronunciation", systemImage: "character.book.closed") }

            PerAppTab()
                .tabItem { Label("Per-App", systemImage: "app.badge") }
        }
        .scenePadding()
        .frame(minWidth: 520, minHeight: 400)
    }
}

// MARK: – Hotkey tab

private struct HotkeyTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Form {
            Section("Permissions") {
                LabeledContent("Accessibility") {
                    if state.accessibilityTrusted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Open System Settings…") {
                            SelectionService.openAccessibilityPreferences()
                        }
                    }
                }
                LabeledContent("Input Monitoring") {
                    Button("Open System Settings…") {
                        SelectionService.openInputMonitoringPreferences()
                    }
                }
                Text("Input Monitoring is needed in apps where the ⌘C fallback is used (Electron apps like VS Code, Slack, Notion).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Shortcuts") {
                KeyboardShortcuts.Recorder("Read selection:", name: .readSelection)
                KeyboardShortcuts.Recorder("Stop reading:", name: .stopReading)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: – Voices tab

private struct VoicesTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Form {
            Section("English") {
                voicePicker(for: .english)
            }
            Section("Polish") {
                voicePicker(for: .polish)
            }
            Section("Playback") {
                let rateBinding = Binding(
                    get: { Double(state.preferences.rate) },
                    set: { state.setRate(Float($0)) }
                )
                let pitchBinding = Binding(
                    get: { Double(state.preferences.pitch) },
                    set: { state.setPitch(Float($0)) }
                )
                Slider(value: rateBinding, in: 0.25...0.75) {
                    Text("Rate")
                } minimumValueLabel: { Text("Slow").font(.caption) } maximumValueLabel: { Text("Fast").font(.caption) }
                Slider(value: pitchBinding, in: 0.75...1.5) {
                    Text("Pitch")
                } minimumValueLabel: { Text("Low").font(.caption) } maximumValueLabel: { Text("High").font(.caption) }
            }
        }
        .formStyle(.grouped)
    }

    private func voicePicker(for language: SpokenLanguage) -> some View {
        VoicePickerView(language: language)
    }
}

// MARK: – Sidecar tab

private struct SidecarTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        SidecarStatusView()
    }
}

// MARK: – Pronunciation tab

private struct PronunciationTab: View {
    @Environment(AppState.self) private var state
    @State private var newPattern = ""
    @State private var newReplacement = ""
    @State private var newLanguage: SpokenLanguage? = nil
    @State private var selection = Set<UUID>()

    var body: some View {
        VStack(alignment: .leading) {
            Text("Replace text before it's spoken. Case-insensitive literal match.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Table(state.pronunciationRules, selection: $selection) {
                TableColumn("Match", value: \.pattern)
                TableColumn("Replacement", value: \.replacement)
                TableColumn("Language") { rule in
                    Text(rule.language?.displayName ?? "Any")
                }
            }
            .frame(minHeight: 160)

            HStack {
                TextField("Match", text: $newPattern)
                TextField("Replacement", text: $newReplacement)
                Picker("", selection: $newLanguage) {
                    Text("Any").tag(SpokenLanguage?.none)
                    Text("EN").tag(SpokenLanguage?.some(.english))
                    Text("PL").tag(SpokenLanguage?.some(.polish))
                }
                .frame(width: 80)
                Button("Add") {
                    let pattern = newPattern.trimmingCharacters(in: .whitespacesAndNewlines)
                    let replacement = newReplacement.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !pattern.isEmpty else { return }
                    state.addPronunciationRule(
                        PronunciationRule(pattern: pattern, replacement: replacement, language: newLanguage)
                    )
                    newPattern = ""
                    newReplacement = ""
                }
                Button("Delete", role: .destructive) {
                    state.removePronunciationRules(selection)
                    selection.removeAll()
                }
                .disabled(selection.isEmpty)
            }
        }
        .padding()
    }
}

// MARK: – Per-app tab

private struct PerAppTab: View {
    @Environment(AppState.self) private var state
    @State private var newBundleID = ""
    @State private var newLanguage: SpokenLanguage = .english
    @State private var selection = Set<UUID>()

    var body: some View {
        VStack(alignment: .leading) {
            Text("Force a language for selections coming from a specific app. Bundle ID e.g. com.apple.Safari.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Table(state.perAppOverrides, selection: $selection) {
                TableColumn("Bundle ID", value: \.bundleID)
                TableColumn("Language") { rule in
                    Text(rule.language.displayName)
                }
            }
            .frame(minHeight: 160)

            HStack {
                TextField("Bundle ID", text: $newBundleID)
                Picker("", selection: $newLanguage) {
                    ForEach(SpokenLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .frame(width: 120)
                Button("Add") {
                    let bundleID = newBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !bundleID.isEmpty else { return }
                    state.addOverride(AppLanguageOverride(bundleID: bundleID, language: newLanguage))
                    newBundleID = ""
                }
                Button("Delete", role: .destructive) {
                    state.removeOverrides(selection)
                    selection.removeAll()
                }
                .disabled(selection.isEmpty)
            }
        }
        .padding()
    }
}
