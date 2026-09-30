import Foundation

/// User configuration, persisted as JSON in Application Support.
/// Edit ~/Library/Application Support/WisprFlow/config.json to change these,
/// or use the menu-bar toggles for the common ones. Decoding tolerates missing
/// keys (older config files keep working and get migrated on next save).
struct Settings: Codable {
    /// Path to the ggml Whisper model.
    var modelPath: String
    /// Path to the whisper.cpp server binary.
    var whisperServerPath: String
    /// Localhost port the bundled whisper-server listens on.
    var whisperPort: Int
    /// Claude API cleanup pass when true (needs ANTHROPIC_API_KEY). Falls back
    /// to local cleanup on any error.
    var aiCleanupEnabled: Bool
    /// Claude model for the cleanup pass.
    var cleanupModel: String
    /// Filler words/phrases removed from every transcript (case-insensitive,
    /// whole-word). Add your own here — no rebuild needed, just restart the app.
    var fillerWords: [String]
    /// Custom dictionary: misheard term -> replacement (case-insensitive, whole-word).
    var dictionary: [String: String]

    static let defaultFillers = [
        "um", "umm", "ummm", "uh", "uhh", "uhhh", "uhm", "erm", "er",
        "ah", "ahh", "hmm", "mm", "mmm", "mhm", "uh-huh",
        "you know", "i mean", "like i said"
    ]

    static let supportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("WisprFlow", isDirectory: true)
    }()
    static let configURL = supportDir.appendingPathComponent("config.json")

    static func defaults() -> Settings {
        Settings(
            modelPath: supportDir.appendingPathComponent("models/ggml-large-v3-turbo-q5_0.bin").path,
            whisperServerPath: "/opt/homebrew/bin/whisper-server",
            whisperPort: 8910,
            aiCleanupEnabled: false,
            cleanupModel: "claude-opus-4-8",
            fillerWords: defaultFillers,
            dictionary: [:]
        )
    }

    // Tolerant decoding: any missing key falls back to the default value, so
    // adding fields never wipes an existing user config (e.g. their modelPath).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings.defaults()
        modelPath         = (try? c.decode(String.self, forKey: .modelPath)) ?? d.modelPath
        whisperServerPath = (try? c.decode(String.self, forKey: .whisperServerPath)) ?? d.whisperServerPath
        whisperPort       = (try? c.decode(Int.self, forKey: .whisperPort)) ?? d.whisperPort
        aiCleanupEnabled  = (try? c.decode(Bool.self, forKey: .aiCleanupEnabled)) ?? d.aiCleanupEnabled
        cleanupModel      = (try? c.decode(String.self, forKey: .cleanupModel)) ?? d.cleanupModel
        fillerWords       = (try? c.decode([String].self, forKey: .fillerWords)) ?? d.fillerWords
        dictionary        = (try? c.decode([String: String].self, forKey: .dictionary)) ?? d.dictionary
    }

    init(modelPath: String, whisperServerPath: String, whisperPort: Int,
         aiCleanupEnabled: Bool, cleanupModel: String, fillerWords: [String],
         dictionary: [String: String]) {
        self.modelPath = modelPath
        self.whisperServerPath = whisperServerPath
        self.whisperPort = whisperPort
        self.aiCleanupEnabled = aiCleanupEnabled
        self.cleanupModel = cleanupModel
        self.fillerWords = fillerWords
        self.dictionary = dictionary
    }

    static func load() -> Settings {
        let s: Settings
        if let data = try? Data(contentsOf: configURL),
           let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            s = decoded
        } else {
            s = defaults()
        }
        s.save()   // migrate schema / write any newly-added defaults back
        return s
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
