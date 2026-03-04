import Foundation

public struct AppConfig: Codable, Equatable {
    public var language: String = "en"
    public var mode: String = "toggle"
    public var hotkey: String = "ctrl+option+space"
    public var modelSize: String = "small"
    public var silenceTimeout: Double = 10.0
    public var silenceThreshold: Double = 0.01
    public var maxDuration: Double = 600.0
    public var autoSubmit: Bool = false
    public var outputMode: String = "paste"
    public var streamingPaste: Bool = false
    public var postProcess: Bool = false

    public init(language: String = "en", mode: String = "toggle",
                hotkey: String = "ctrl+option+space", modelSize: String = "small",
                silenceTimeout: Double = 10.0, silenceThreshold: Double = 0.01,
                maxDuration: Double = 600.0, autoSubmit: Bool = false,
                outputMode: String = "paste", streamingPaste: Bool = false,
                postProcess: Bool = false) {
        self.language = language
        self.mode = mode
        self.hotkey = hotkey
        self.modelSize = modelSize
        self.silenceTimeout = silenceTimeout
        self.silenceThreshold = silenceThreshold
        self.maxDuration = maxDuration
        self.autoSubmit = autoSubmit
        self.outputMode = outputMode
        self.streamingPaste = streamingPaste
        self.postProcess = postProcess
    }

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

    // Custom decoder so partial JSON (missing keys) falls back to defaults
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppConfig()
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? defaults.language
        mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? defaults.mode
        hotkey = try c.decodeIfPresent(String.self, forKey: .hotkey) ?? defaults.hotkey
        modelSize = try c.decodeIfPresent(String.self, forKey: .modelSize) ?? defaults.modelSize
        silenceTimeout = try c.decodeIfPresent(Double.self, forKey: .silenceTimeout) ?? defaults.silenceTimeout
        silenceThreshold = try c.decodeIfPresent(Double.self, forKey: .silenceThreshold) ?? defaults.silenceThreshold
        maxDuration = try c.decodeIfPresent(Double.self, forKey: .maxDuration) ?? defaults.maxDuration
        autoSubmit = try c.decodeIfPresent(Bool.self, forKey: .autoSubmit) ?? defaults.autoSubmit
        outputMode = try c.decodeIfPresent(String.self, forKey: .outputMode) ?? defaults.outputMode
        streamingPaste = try c.decodeIfPresent(Bool.self, forKey: .streamingPaste) ?? defaults.streamingPaste
        postProcess = try c.decodeIfPresent(Bool.self, forKey: .postProcess) ?? defaults.postProcess
    }
}

public enum ConfigManager {
    private static var configURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TranscriptWhatYouHear", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }()

    public static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: configURL),
              let cfg = try? JSONDecoder().decode(AppConfig.self, from: data)
        else {
            return AppConfig()
        }
        return cfg
    }

    public static func save(_ cfg: AppConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(cfg) else { return }
        try? data.write(to: configURL, options: .atomic)
    }
}
