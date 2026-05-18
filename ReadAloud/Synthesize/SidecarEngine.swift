import Foundation
import AVFoundation

/// Streams PCM from the local Python sidecar's OpenAI-compatible
/// `/v1/audio/speech` endpoint into a shared `StreamingPlayer`.
///
/// Pipelining: chunks the input by sentence, then fetches chunk *N+1*'s PCM
/// while chunk *N* is being awaited, so the sidecar is never idle waiting on
/// the client. Buffers reach the player in strict sentence order — no
/// interleaving.
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
        let chunks = SentenceChunker.chunks(from: text)
        guard !chunks.isEmpty else { return }
        Log.tts.notice("SidecarEngine pipelining \(chunks.count, privacy: .public) chunks via \(modelID, privacy: .public)")

        let task = Task<Void, Never> { [endpoint, player] in
            func render(_ chunk: String) -> Task<[Float]?, Never> {
                Task<[Float]?, Never>.detached(priority: .userInitiated) {
                    let request = Request(
                        model: modelID,
                        voice: voiceID,
                        input: chunk,
                        stream: false,
                        response_format: "pcm",
                        sample_rate: 24_000
                    )
                    return await Self.fetchPCM(endpoint: endpoint, request: request)
                }
            }

            // Kick off chunk 0; thereafter keep one chunk pre-rendering ahead.
            var pending: Task<[Float]?, Never>? = render(chunks[0])
            for i in 0..<chunks.count {
                if Task.isCancelled {
                    pending?.cancel()
                    break
                }
                let next: Task<[Float]?, Never>? =
                    (i + 1 < chunks.count) ? render(chunks[i + 1]) : nil

                if let pcm = await pending?.value, !Task.isCancelled {
                    await MainActor.run {
                        player.enqueue(pcm, sampleRate: 24_000)
                    }
                }
                pending = next
            }
        }
        currentTask = task
        await task.value
        Log.tts.notice("SidecarEngine speak finished")
    }

    func stop() {
        currentTask?.cancel()
        player.flush()
    }

    /// Downloads a chunk's PCM (int16, little-endian, 24 kHz) into a Float
    /// array. Returns `nil` on transport / server errors so the loop in
    /// `speak` skips the chunk instead of throwing.
    private static func fetchPCM(endpoint: URL, request: Request) async -> [Float]? {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 120
        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            Log.tts.error("Sidecar request encode failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                Log.tts.error("Sidecar returned HTTP \(http.statusCode, privacy: .public) — body: \(String(data: data, encoding: .utf8) ?? "<binary>", privacy: .public)")
                return nil
            }
            return Self.decodePCM16(data)
        } catch {
            if !(error is CancellationError) {
                Log.tts.error("Sidecar fetch error: \(error.localizedDescription, privacy: .public)")
            }
            return nil
        }
    }

    /// Decode interleaved int16 little-endian PCM into normalized Float32.
    private static func decodePCM16(_ data: Data) -> [Float] {
        let sampleCount = data.count / 2
        var floats = [Float](repeating: 0, count: sampleCount)
        data.withUnsafeBytes { raw in
            let ints = raw.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                floats[i] = Float(ints[i]) / 32_768.0
            }
        }
        return floats
    }
}
