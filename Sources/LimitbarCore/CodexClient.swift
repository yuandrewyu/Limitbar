import Foundation

/// Uses the installed CLI's documented app-server protocol. No model turns are created.
public enum CodexClient {
    public static func findExecutable(override: String) throws -> URL {
        let candidates: [String]
        if !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            candidates = [NSString(string: override).expandingTildeInPath]
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            candidates = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex",
                          "\(home)/.local/bin/codex", "\(home)/.npm-global/bin/codex"]
        }
        guard let path = candidates.first(where: {
            $0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: $0)
        }) else {
            throw ClientError.message("Codex CLI not found. Set its absolute path in Settings, then sign in with ‘codex login’ on your Mac.")
        }
        return URL(fileURLWithPath: path)
    }

    public static func fetch(executable: URL, timeout: TimeInterval = 20) async throws -> UsageSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let client = RPCProcess(executable: executable, timeout: timeout)
                    defer { client.close() }
                    try client.start()
                    _ = try client.request(id: 0, method: "initialize", params: [
                        "clientInfo": ["name": "limitbar", "title": "Limitbar", "version": "0.1.0"]
                    ])
                    try client.notify(method: "initialized")
                    let account = try client.request(id: 1, method: "account/read",
                                                     params: ["refreshToken": false])
                    guard let info = account["account"] as? [String: Any],
                          info["type"] as? String == "chatgpt" else {
                        throw ClientError.message("Sign in to Codex CLI with your ChatGPT subscription using ‘codex login’.")
                    }
                    let result = try client.request(id: 2, method: "account/rateLimits/read")
                    let data = try JSONSerialization.data(withJSONObject: result)
                    continuation.resume(returning: try UsageDecoders.codexRateLimits(data))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private enum ClientError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

/// All waits happen on a utility queue, with a deadline and bounded output.
private final class RPCProcess {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let condition = NSCondition()
    private var buffer = Data()
    private var replies: [Int: [String: Any]] = [:]
    private var ended = false
    private var overflow = false
    private let deadline: Date

    init(executable: URL, timeout: TimeInterval) {
        deadline = Date().addingTimeInterval(timeout)
        process.executableURL = executable
        process.arguments = ["app-server"]
        // GUI apps often inherit a minimal PATH. Support common Node-based CLI installs.
        var environment = ProcessInfo.processInfo.environment
        let inheritedPath = environment["PATH"] ?? "/usr/bin:/bin"
        environment["PATH"] = "\(executable.deletingLastPathComponent().path):/opt/homebrew/bin:/usr/local/bin:\(inheritedPath)"
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
    }

    func start() throws {
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            self?.receive(data)
        }
        process.terminationHandler = { [weak self] _ in
            guard let self else { return }
            self.condition.lock()
            self.ended = true
            self.condition.broadcast()
            self.condition.unlock()
        }
        try process.run()
        // Close this process's copies of the child's pipe endpoints, so EOF is observable.
        try? output.fileHandleForWriting.close()
        try? input.fileHandleForReading.close()
    }

    func notify(method: String) throws {
        try send(["method": method, "params": [:]])
    }

    func request(id: Int, method: String, params: [String: Any] = [:]) throws -> [String: Any] {
        try send(["id": id, "method": method, "params": params])
        condition.lock()
        defer { condition.unlock() }
        while replies[id] == nil && !ended && !overflow {
            if !condition.wait(until: deadline) { break }
        }
        guard let reply = replies.removeValue(forKey: id) else {
            throw ClientError.message("Codex did not return usage in time. Check your CLI version, login, and connection.")
        }
        if let error = reply["error"] as? [String: Any] {
            let code = (error["code"] as? Int).map(String.init) ?? "unknown"
            // Do not surface raw RPC payloads, which could contain account details.
            throw ClientError.message("Codex rejected the usage request (\(code)). Check your CLI version and ChatGPT login.")
        }
        guard let result = reply["result"] as? [String: Any] else {
            throw ClientError.message("Codex returned an unexpected response format.")
        }
        return result
    }

    private func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object,
                                              options: [.sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    private func receive(_ data: Data) {
        condition.lock()
        defer { condition.broadcast(); condition.unlock() }
        guard !data.isEmpty else { ended = true; return }
        buffer.append(data)
        guard buffer.count <= 4 * 1024 * 1024 else { overflow = true; buffer.removeAll(); return }
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
               let id = object["id"] as? Int, (0...2).contains(id), object["method"] == nil {
                replies[id] = object
            }
        }
    }

    func close() {
        output.fileHandleForReading.readabilityHandler = nil
        process.terminationHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        try? output.fileHandleForReading.close()
    }
}
