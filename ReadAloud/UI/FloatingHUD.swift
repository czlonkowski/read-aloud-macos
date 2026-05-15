import SwiftUI
import AppKit

/// Transient panel shown while speech is in progress. v0.1 stub — the menu-bar
/// extra already exposes pause/stop. A future iteration can promote this into
/// an `NSPanel`-hosted floating window with progress and a teleprompter view.
struct FloatingHUD: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if case .idle = state.playbackState {
            EmptyView()
        } else {
            HStack(spacing: 12) {
                Image(systemName: "speaker.wave.3.fill")
                if let request = state.lastRead {
                    Text(request.text.prefix(80) + (request.text.count > 80 ? "…" : ""))
                        .font(.callout)
                        .lineLimit(2)
                }
                Spacer()
                Button(action: { state.pause() }) { Image(systemName: "pause.fill") }
                Button(action: { state.stop() }) { Image(systemName: "stop.fill") }
            }
            .padding(12)
            .frame(width: Theme.hudWidth)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
    }
}
