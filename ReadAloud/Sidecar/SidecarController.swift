import Foundation
import AppKit

/// Owns the lifecycle of the Python TTS sidecar (start / stop / health).
/// The sidecar is a `launchd` LaunchAgent installed under
/// `~/Library/LaunchAgents/com.czlonkowski.readaloud-sidecar.plist`.
@MainActor
final class SidecarController {
    enum Status: Equatable {
        case unknown
        case notInstalled
        case stopped
        case starting
        case running
        case failed(String)
    }

    static let label = "com.czlonkowski.readaloud-sidecar"
    static let healthURL = URL(string: "http://127.0.0.1:8000/healthz")!
    static let warmupURL = URL(string: "http://127.0.0.1:8000/v1/warmup")!

    private(set) var status: Status = .unknown
    private(set) var lastError: String?

    /// Quick HTTP health probe with a 250ms timeout.
    func healthCheck() async -> Bool {
        var request = URLRequest(url: Self.healthURL)
        request.timeoutInterval = 0.25
        request.httpMethod = "GET"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// Kicks the launch agent. Idempotent: returns true if running or already started.
    @discardableResult
    func start() async -> Bool {
        if await healthCheck() {
            status = .running
            return true
        }
        guard isInstalled() else {
            status = .notInstalled
            return false
        }
        status = .starting
        runLaunchctl(["kickstart", "-k", "gui/\(getuid())/\(Self.label)"])
        for _ in 0..<40 { // up to 10s
            try? await Task.sleep(nanoseconds: 250_000_000)
            if await healthCheck() {
                status = .running
                return true
            }
        }
        status = .failed("Sidecar did not become healthy within 10s")
        return false
    }

    /// Fire-and-forget POST to /v1/warmup so the sidecar starts loading both
    /// engines in the background. We don't await completion — first synth
    /// will still block until models are loaded if needed.
    func warmUp() {
        Task {
            var request = URLRequest(url: Self.warmupURL)
            request.httpMethod = "POST"
            request.timeoutInterval = 120
            do {
                _ = try await URLSession.shared.data(for: request)
                Log.sidecar.notice("Warmup request completed")
            } catch {
                Log.sidecar.error("Warmup failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func stop() {
        runLaunchctl(["bootout", "gui/\(getuid())/\(Self.label)"])
        status = .stopped
    }

    func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: plistPath().path)
    }

    func plistPath() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
            .appendingPathComponent("\(Self.label).plist")
    }

    @discardableResult
    private func runLaunchctl(_ args: [String]) -> Int32 {
        let process = Process()
        process.launchPath = "/bin/launchctl"
        process.arguments = args
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            Log.sidecar.error("launchctl \(args.joined(separator: " "), privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return -1
        }
    }
}
