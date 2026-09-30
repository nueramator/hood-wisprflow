import Foundation

/// User configuration, persisted as JSON in Application Support.
/// Edit ~/Library/Application Support/WisprFlow/config.json to change these,
/// or use the menu-bar item toggles for the common ones.
struct Settings: Codable {
    /// Path to the ggml Whisper model. Downloaded by scripts/setup.sh.
    var modelPath: String
    /// Path to the whisper.cpp server binary (from `brew install whisper-cpp`).
    var whisperServerPath: String
    /// Localhost port the bundled whisper-server listens on.
    var whisperPort: Int
    /// Turn raw transcript into polished text via the Claude API when true.
    /// Requires ANTHROPIC_API_KEY in the environment. Falls back to local
    /// cleanup on any error or timeout.
    var aiCleanupEnabled: Bool
    /// Claude model for the cleanup pass. Default per Anthropic guidance is
    /// claude-opus-4-8; for a snappier dictation feel switch to
    /// "claude-haiku-4-5" (much faster/cheaper, plenty for cleanup).
    var cleanupModel: String
    /// Custom dictionary: spoken/misheard term -> replacement. Applied after
    /// transcription (case-insensitive whole-word match).
    var dictionary: [String: String]

    static let supportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("WisprFlow", isDirectory: true)
    }()

    static let configURL = supportDir.appendingPathComponent("config.json")

    static func defaults() -> Settings {
        Settings(
            modelPath: supportDir.appendingPathComponent("models/ggml-base.en.bin").path,
            whisperServerPath: "/opt/homebrew/bin/whisper-server",
            whisperPort: 8910,
            aiCleanupEnabled: false,
            cleanupModel: "claude-opus-4-8",
            dictionary: [:]
        )
    }

    static func load() -> Settings {
        guard let data = try? Data(contentsOf: configURL),
              let decoded = try? JSONDecoder().decode(Settings.self, from: data) else {
            let d = defaults()
            d.save()
            return d
        }
        return decoded
    }

    func save() {
        try? FileManager.default.createDirectory(at: Settings.supportDir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self) {
            try? data.write(to: Settings.configURL)
        }
    }
}
