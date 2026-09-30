import Foundation

/// Manages a local whisper.cpp server subprocess (model stays resident for low
/// latency) and transcribes WAV files by POSTing to its /inference endpoint.
/// Fully local — no network, unlimited, private.
final class WhisperEngine {
    private let settings: Settings
    private var process: Process?
    private var baseURL: URL { URL(string: "http://127.0.0.1:\(settings.whisperPort)")! }

    enum EngineError: Error, CustomStringConvertible {
        case binaryMissing(String)
        case modelMissing(String)
        case notReady
        case badResponse
        var description: String {
            switch self {
            case .binaryMissing(let p): return "whisper-server not found at \(p). Run scripts/setup.sh."
            case .modelMissing(let p): return "Whisper model not found at \(p). Run scripts/setup.sh."
            case .notReady: return "whisper-server did not become ready in time."
            case .badResponse: return "whisper-server returned an unexpected response."
            }
        }
    }

    init(settings: Settings) {
        self.settings = settings
    }

    /// Launches whisper-server with the model preloaded and waits for it to
    /// answer. Blocking; call off the main thread at startup.
    func start() throws {
        guard FileManager.default.isExecutableFile(atPath: settings.whisperServerPath) else {
            throw EngineError.binaryMissing(settings.whisperServerPath)
        }
        guard FileManager.default.fileExists(atPath: settings.modelPath) else {
            throw EngineError.modelMissing(settings.modelPath)
        }

        let p = Process()
        p.executableURL = URL(fileURLToPath: settings.whisperServerPath)
        p.arguments = [
            "--model", settings.modelPath,
            "--host", "127.0.0.1",
            "--port", "\(settings.whisperPort)",
            "--no-timestamps"
        ]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        process = p

        // Poll until the server responds (model load can take a moment).
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if ping() { return }
            Thread.sleep(forTimeInterval: 0.3)
        }
        throw EngineError.notReady
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    private func ping() -> Bool {
        var request = URLRequest(url: baseURL)
        request.timeoutInterval = 1
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        URLSession.shared.dataTask(with: request) { _, response, _ in
            // Any HTTP response means the socket is up.
            if response is HTTPURLResponse { ok = true }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 1.5)
        return ok
    }

    /// Transcribes a WAV file. Blocking; call off the main thread.
    func transcribe(wavURL: URL) throws -> String {
        let boundary = "wispr-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appendingPathComponent("inference"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let wavData = try Data(contentsOf: wavURL)
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        field("temperature", "0.0")
        field("response_format", "json")
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let sem = DispatchSemaphore(value: 0)
        var result = ""
        var thrown: Error?
        URLSession.shared.dataTask(with: request) { data, _, error in
            defer { sem.signal() }
            if let error { thrown = error; return }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = json["text"] as? String else {
                thrown = EngineError.badResponse
                return
            }
            result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }.resume()
        _ = sem.wait(timeout: .now() + 65)
        if let thrown { throw thrown }
        return result
    }
}

private extension URL {
    init(fileURLToPath path: String) { self.init(fileURLWithPath: path) }
}
