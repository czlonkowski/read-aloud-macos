import SwiftUI

struct MenuBarLabel: View {
    let state: AppState

    var body: some View {
        Image(systemName: symbolName)
    }

    private var symbolName: String {
        switch state.playbackState {
        case .idle:               "speaker.wave.2"
        case .preparing:          "speaker.wave.2.bubble"
        case .speaking:           "speaker.wave.3.fill"
        case .paused:             "speaker.slash"
        }
    }
}
