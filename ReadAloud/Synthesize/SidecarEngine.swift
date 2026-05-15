import Foundation
import AVFoundation

/// Streams PCM from the local Python sidecar's OpenAI-compatible
/// `/v1/audio/speech` endpoint into a shared `StreamingPlayer`.
///
/// Wire only — won't be exercised until the sidecar is installed.
@MainActor
final class SidecarEngine {
    private let endpoint = URL(string: "http://127.0.0.1:8000/v1/audio/speech")!
    private var currentTask: Task<Void, Never>?
    private let player: StreamingPlayer

    init(player: StreamingPlayer) {
        self.player = player
    }

    struct Request: Encodable {
        let model: String
        let voice: String
        let input: String
        let stream: Bool
        let response_format: String
        let sample_rate: Int
    }

    func speak(
        _ text: String,
        language: SpokenLanguage,
        voiceID: String,
        modelID: String,
        rate: Float
    ) async {
        currentTask?.cancel()
        let task = Task<Void, Never> { [endpoint, player] in
            let chunks = SentenceChunker.chunks(from: text)
            for chunk in chunks {
                if Task.isCancelled { break }
                await Self.streamOne(
                    endpoint: endpoint,
                    request: .init(
                        model: modelID,
                        voice: voiceID,
                        input: chunk,
                        stream: true,
                        response_format: "pcm",
                        sample_rate: 24_000
                    ),
                    into: player
                )
            }
        }
        currentTask = task
        await task.value
    }

    func stop() {
        currentTask?.cancel()
        player.flush()
    }

    private static func streamOne(
        endpoint: URL,
        request: Request,
        into player: StreamingPlayer
    ) async {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 60
        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            Log.tts.error("Sidecar request encode failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                Log.tts.error("Sidecar returned HTTP \(http.statusCode, privacy: .public)")
                return
            }
            var pair = [UInt8](repeating: 0, count: 2)
            var pairFill = 0
            var floatBuf: [Float] = []
            floatBuf.reserveCapacity(4_800)
            for try await byte in bytes {
                if Task.isCancelled { break }
                pair[pairFill] = byte
                pairFill += 1
                if pairFill == 2 {
                    let raw = UInt16(pair[0]) | (UInt16(pair[1]) << 8)
                    let sample = Int16(bitPattern: raw)
                    floatBuf.append(Float(sample) / 32_768.0)
                    pairFill = 0
                    if floatBuf.count >= 4_800 {
                        await MainActor.run { player.enqueue(floatBuf, sampleRate: 24_000) }
                        floatBuf.removeAll(keepingCapacity: true)
                    }
                }
            }
            if !floatBuf.isEmpty {
                let tail = floatBuf
                await MainActor.run { player.enqueue(tail, sampleRate: 24_000) }
            }
        } catch {
            if !(error is CancellationError) {
                Log.tts.error("Sidecar stream error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
