import Foundation
import Darwin

/// All memory mutations go through gbrain. Search explicitly stays offline.
struct BrainClient {
    let executable: URL

    init(executable: URL? = nil) {
        self.executable = executable ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("gbrain/bin/gbrain")
    }

    var available: Bool { FileManager.default.isExecutableFile(atPath: executable.path) }

    func search(query: String, kind: String, entity: String, source: String, status: String) async throws -> [BrainFact] {
        var arguments = ["search", query, "--json", "--local", "-k", "100", "--status", status]
        if !kind.isEmpty { arguments += ["--kind", kind] }
        if !entity.isEmpty { arguments += ["--entity", entity] }
        if !source.isEmpty { arguments += ["--source", source] }
        return try await decode([BrainFact].self, arguments: arguments)
    }

    func apiAvailable() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:8760/health") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            return body["ok"] as? Bool == true && body["service"] as? String == "gbrain"
        } catch { return false }
    }

    func candidates() async throws -> [BrainCandidate] {
        try await decode([BrainCandidate].self, arguments: ["candidates", "--json", "--limit", "200"])
    }

    func review(id: Int, accept: Bool) async throws -> Int {
        struct Change: Decodable { let changed: Int }
        return try await decode(Change.self, arguments: [accept ? "accept" : "reject", String(id), "--json"]).changed
    }

    private func decode<T: Decodable>(_ type: T.Type, arguments: [String]) async throws -> T {
        let command = BrainCommand(executable: executable, arguments: arguments)
        let data = try await withTaskCancellationHandler(operation: {
            try await Task.detached(priority: .userInitiated) { try command.run(timeout: 15) }.value
        }, onCancel: { command.cancel() })
        try Task.checkCancellation()
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw BrainClientError.invalidResponse }
    }
}

enum BrainClientError: LocalizedError {
    case unavailable, timedOut, invalidResponse, failed
    var errorDescription: String? {
        switch self {
        case .unavailable: return BrainCopy.text("La commande gbrain n’est pas installée ou n’est pas exécutable.", "The gbrain command is not installed or executable.")
        case .timedOut: return BrainCopy.text("gbrain n’a pas répondu dans les 15 secondes. Réessaie.", "gbrain did not respond within 15 seconds. Try again.")
        case .invalidResponse: return BrainCopy.text("La réponse gbrain est incompatible. Vérifie que sa mise à jour est installée.", "The gbrain response is incompatible. Check that its update is installed.")
        case .failed: return BrainCopy.text("gbrain n’a pas pu terminer cette opération. La mémoire n’a pas été confirmée comme modifiée.", "gbrain could not complete this operation. No memory change has been confirmed.")
        }
    }
}

private final class BrainCommand: @unchecked Sendable {
    private let executable: URL
    private let arguments: [String]
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var timedOut = false

    init(executable: URL, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let running = process
        lock.unlock()
        stop(running)
    }

    private func stop(_ process: Process?) {
        guard let process, process.isRunning else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    func run(timeout: TimeInterval) throws -> Data {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw BrainClientError.unavailable }
        let task = Process()
        task.executableURL = executable
        task.arguments = arguments
        let output = Pipe(), errors = Pipe()
        task.standardOutput = output
        task.standardError = errors
        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        process = task
        do { try task.run() } catch { lock.unlock(); throw BrainClientError.unavailable }
        lock.unlock()

        let expiration = DispatchWorkItem { [weak self, weak task] in
            guard let self, let task, task.isRunning else { return }
            self.lock.lock()
            self.timedOut = true
            self.lock.unlock()
            self.stop(task)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: expiration)
        // Drain stderr concurrently so a full pipe cannot prevent the child from exiting.
        let stderrDone = DispatchGroup()
        stderrDone.enter()
        DispatchQueue.global().async {
            _ = errors.fileHandleForReading.readDataToEndOfFile()
            stderrDone.leave()
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        stderrDone.wait()
        expiration.cancel()
        lock.lock()
        let wasCancelled = cancelled, expired = timedOut
        process = nil
        lock.unlock()
        if wasCancelled { throw CancellationError() }
        if expired { throw BrainClientError.timedOut }
        guard task.terminationStatus == 0 else { throw BrainClientError.failed }
        return data
    }
}
