import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Read the currently-selected text. Default: ⌥⌘R.
    static let readSelection = Self(
        "readSelection",
        default: .init(.r, modifiers: [.option, .command])
    )

    /// Stop any in-flight speech. Default: ⌥⌘.
    static let stopReading = Self(
        "stopReading",
        default: .init(.period, modifiers: [.option, .command])
    )
}
