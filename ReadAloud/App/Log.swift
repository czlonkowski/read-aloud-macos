import Foundation
import os

enum Log {
    static let subsystem = "com.czlonkowski.ReadAloud"

    static let app       = Logger(subsystem: subsystem, category: "app")
    static let hotkey    = Logger(subsystem: subsystem, category: "hotkey")
    static let selection = Logger(subsystem: subsystem, category: "selection")
    static let tts       = Logger(subsystem: subsystem, category: "tts")
    static let audio     = Logger(subsystem: subsystem, category: "audio")
    static let sidecar   = Logger(subsystem: subsystem, category: "sidecar")
}
