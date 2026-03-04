import Foundation

struct AppConfig: Codable {
    var language: String = "en"
    var mode: String = "toggle"
    var hotkey: String = "ctrl+option+space"
    var modelSize: String = "small"
    var silenceTimeout: Double = 10.0
    var silenceThreshold: Double = 0.01
    var maxDuration: Double = 600.0
    var autoSubmit: Bool = false
    var outputMode: String = "paste"
    var streamingPaste: Bool = false
    var postProcess: Bool = false

    enum CodingKeys: String, CodingKey {
        case language, mode, hotkey
        case modelSize = "model_size"
        case silenceTimeout = "silence_timeout"
        case silenceThreshold = "silence_threshold"
        case maxDuration = "max_duration"
        case autoSubmit = "auto_submit"
        case outputMode = "output_mode"
        case streamingPaste = "streaming_paste"
        case postProcess = "post_process"
    }
}

enum ConfigManager {
    private static var configURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TranscriptWhatYouHear", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }()

    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: configURL),
              let cfg = try? JSONDecoder().decode(AppConfig.self, from: data)
        else {
            return AppConfig()
        }
        return cfg
    }

    static func save(_ cfg: AppConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(cfg) else { return }
        try? data.write(to: configURL, options: .atomic)
    }
}
