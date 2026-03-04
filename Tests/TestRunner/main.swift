import Foundation
import AppKit
import TranscriptLib

// ───────────────────────────────────────────────────────────────────────
// Minimal test framework (no XCTest / Xcode needed)
// ───────────────────────────────────────────────────────────────────────

var totalTests = 0
var passedTests = 0
var failedTests: [(String, String)] = []

func test(_ name: String, _ body: () throws -> Void) {
    totalTests += 1
    do {
        try body()
        passedTests += 1
        print("  ✅ \(name)")
    } catch {
        failedTests.append((name, "\(error)"))
        print("  ❌ \(name): \(error)")
    }
}

struct AssertionError: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: Bool, _ msg: String = "Assertion failed", file: String = #file, line: Int = #line) throws {
    guard condition else { throw AssertionError(description: "\(msg) (\(file):\(line))") }
}

func expectEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String = "", file: String = #file, line: Int = #line) throws {
    guard a == b else {
        let detail = msg.isEmpty ? "Expected \(a) == \(b)" : msg
        throw AssertionError(description: "\(detail) (\(file):\(line))")
    }
}

func expectNear(_ a: Double, _ b: Double, accuracy: Double = 0.001) throws {
    guard abs(a - b) < accuracy else {
        throw AssertionError(description: "Expected \(a) ≈ \(b) (±\(accuracy))")
    }
}

// ───────────────────────────────────────────────────────────────────────
// PostProcessor Tests
// ───────────────────────────────────────────────────────────────────────

print("\n📝 PostProcessor")

test("Removes English filler words") {
    let result = PostProcessor.process("So um I mean the thing is basically right")
    try expect(!result.lowercased().contains("um"), "Should remove 'um'")
    try expect(!result.lowercased().contains("i mean"), "Should remove 'i mean'")
    try expect(!result.lowercased().contains("basically"), "Should remove 'basically'")
}

test("Removes Czech filler words") {
    let result = PostProcessor.process("Prostě jako vlastně to funguje")
    try expect(!result.lowercased().contains("prostě"), "Should remove 'prostě'")
    try expect(!result.lowercased().contains("jako"), "Should remove 'jako'")
    try expect(!result.lowercased().contains("vlastně"), "Should remove 'vlastně'")
    try expect(result.contains("funguje"), "Should keep 'funguje'")
}

test("Collapses multiple spaces") {
    let result = PostProcessor.process("hello    world")
    try expect(!result.contains("  "), "No double spaces")
    try expect(result.lowercased().contains("hello"), "Keeps 'hello'")
    try expect(result.lowercased().contains("world"), "Keeps 'world'")
}

test("Capitalizes first letter") {
    let result = PostProcessor.process("hello world")
    try expect(result.hasPrefix("H"), "Starts with 'H'")
}

test("Empty input returns empty") {
    try expectEqual(PostProcessor.process(""), "")
}

test("Only filler words returns empty") {
    try expectEqual(PostProcessor.process("um uh er ah"), "")
}

test("Preserves non-filler content") {
    try expectEqual(PostProcessor.process("The weather is nice today"), "The weather is nice today")
}

test("Multi-word filler phrases removed") {
    let result = PostProcessor.process("you know it was kind of interesting")
    try expect(!result.lowercased().contains("you know"), "Removes 'you know'")
    try expect(!result.lowercased().contains("kind of"), "Removes 'kind of'")
    try expect(result.contains("interesting"), "Keeps 'interesting'")
}

test("Trims whitespace") {
    try expectEqual(PostProcessor.process("  hello  "), "Hello")
}

// ───────────────────────────────────────────────────────────────────────
// AppConfig Tests
// ───────────────────────────────────────────────────────────────────────

print("\n⚙️  AppConfig")

test("Default values are correct") {
    let cfg = AppConfig()
    try expectEqual(cfg.language, "en")
    try expectEqual(cfg.mode, "toggle")
    try expectEqual(cfg.hotkey, "ctrl+option+space")
    try expectEqual(cfg.modelSize, "small")
    try expectEqual(cfg.silenceTimeout, 10.0)
    try expectEqual(cfg.silenceThreshold, 0.01)
    try expectEqual(cfg.maxDuration, 600.0)
    try expectEqual(cfg.autoSubmit, false)
    try expectEqual(cfg.outputMode, "paste")
    try expectEqual(cfg.streamingPaste, false)
    try expectEqual(cfg.postProcess, false)
}

test("Codable round-trip preserves all fields") {
    var cfg = AppConfig()
    cfg.language = "cs"
    cfg.mode = "push_to_talk"
    cfg.hotkey = "cmd+shift+r"
    cfg.modelSize = "medium"
    cfg.silenceTimeout = 5.0
    cfg.silenceThreshold = 0.02
    cfg.maxDuration = 120.0
    cfg.autoSubmit = true
    cfg.outputMode = "type"
    cfg.streamingPaste = true
    cfg.postProcess = true

    let data = try JSONEncoder().encode(cfg)
    let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
    try expectEqual(cfg, decoded)
}

test("JSON snake_case keys map correctly") {
    let json = """
    {
        "language": "de", "mode": "toggle", "hotkey": "ctrl+space",
        "model_size": "large", "silence_timeout": 8.0,
        "silence_threshold": 0.005, "max_duration": 300.0,
        "auto_submit": true, "output_mode": "clipboard",
        "streaming_paste": false, "post_process": true
    }
    """.data(using: .utf8)!

    let cfg = try JSONDecoder().decode(AppConfig.self, from: json)
    try expectEqual(cfg.language, "de")
    try expectEqual(cfg.modelSize, "large")
    try expectEqual(cfg.silenceTimeout, 8.0)
    try expectEqual(cfg.maxDuration, 300.0)
    try expectEqual(cfg.autoSubmit, true)
    try expectEqual(cfg.outputMode, "clipboard")
    try expectEqual(cfg.postProcess, true)
}

test("Partial JSON uses defaults for missing fields") {
    let json = """
    { "language": "fr" }
    """.data(using: .utf8)!

    let cfg = try JSONDecoder().decode(AppConfig.self, from: json)
    try expectEqual(cfg.language, "fr")
    try expectEqual(cfg.mode, "toggle")
    try expectEqual(cfg.outputMode, "paste")
}

// ───────────────────────────────────────────────────────────────────────
// HotkeyManager Tests
// ───────────────────────────────────────────────────────────────────────

print("\n⌨️  HotkeyManager")

test("Display string for ctrl+option+space") {
    try expectEqual(HotkeyManager.displayString(for: "ctrl+option+space"), "⌃⌥Spc")
}

test("Display string for cmd+shift+r") {
    try expectEqual(HotkeyManager.displayString(for: "cmd+shift+r"), "⌘⇧R")
}

test("Display string with alternate names (control+alt)") {
    try expectEqual(HotkeyManager.displayString(for: "control+alt+a"), "⌃⌥A")
}

test("Display string for command+b") {
    try expectEqual(HotkeyManager.displayString(for: "command+b"), "⌘B")
}

test("Parse ctrl+option+space") {
    let (key, mods) = HotkeyManager.parse("ctrl+option+space")
    try expect(key != nil, "Key should not be nil")
    try expect(mods.contains(.control), "Should have control")
    try expect(mods.contains(.option), "Should have option")
    try expect(!mods.contains(.command), "Should not have command")
    try expect(!mods.contains(.shift), "Should not have shift")
}

test("Parse cmd+shift+r") {
    let (key, mods) = HotkeyManager.parse("cmd+shift+r")
    try expect(key != nil, "Key should not be nil")
    try expect(mods.contains(.command), "Should have command")
    try expect(mods.contains(.shift), "Should have shift")
}

test("Parse invalid key returns nil") {
    let (key, _) = HotkeyManager.parse("ctrl+option+unknownkey")
    try expect(key == nil, "Key should be nil for unknown key")
}

test("Parse key without modifiers") {
    let (key, mods) = HotkeyManager.parse("space")
    try expect(key != nil, "Key should not be nil")
    try expect(mods.isEmpty, "Modifiers should be empty")
}

test("Parse function keys f1-f12") {
    let (key1, _) = HotkeyManager.parse("ctrl+f1")
    try expect(key1 != nil, "f1 should parse")
    let (key12, _) = HotkeyManager.parse("ctrl+f12")
    try expect(key12 != nil, "f12 should parse")
}

test("Parse number keys 0-9") {
    for i in 0...9 {
        let (key, _) = HotkeyManager.parse("cmd+\(i)")
        try expect(key != nil, "Number key \(i) should parse")
    }
}

test("Parse all letter keys a-z") {
    for letter in "abcdefghijklmnopqrstuvwxyz" {
        let (key, _) = HotkeyManager.parse("ctrl+\(letter)")
        try expect(key != nil, "Letter '\(letter)' should parse")
    }
}

test("Parse special keys") {
    let specialKeys = ["return", "enter", "tab", "escape", "esc",
                       "delete", "backspace", "up", "down", "left", "right"]
    for name in specialKeys {
        let (key, _) = HotkeyManager.parse("ctrl+\(name)")
        try expect(key != nil, "Special key '\(name)' should parse")
    }
}

test("Parse is case insensitive") {
    let (key1, mods1) = HotkeyManager.parse("CTRL+OPTION+SPACE")
    let (key2, mods2) = HotkeyManager.parse("ctrl+option+space")
    try expect(key1 != nil && key2 != nil, "Both should parse")
    try expect(mods1 == mods2, "Modifiers should be equal")
}

// ───────────────────────────────────────────────────────────────────────
// AudioRecorder RMS Tests
// ───────────────────────────────────────────────────────────────────────

print("\n🎙️ AudioRecorder RMS")

test("RMS of silence is zero") {
    let rms = AudioRecorder.computeRMS([Float](repeating: 0, count: 1000))
    try expectNear(rms, 0, accuracy: 0.0001)
}

test("RMS of constant signal") {
    let rms = AudioRecorder.computeRMS([Float](repeating: 0.5, count: 1000))
    try expectNear(rms, 0.5, accuracy: 0.001)
}

test("RMS of sine wave ≈ 1/√2") {
    let count = 44100
    var samples = [Float](repeating: 0, count: count)
    for i in 0..<count {
        samples[i] = sin(2 * .pi * Float(i) / Float(count) * 440)
    }
    let rms = AudioRecorder.computeRMS(samples)
    try expectNear(rms, 1.0 / sqrt(2.0), accuracy: 0.01)
}

test("RMS of empty array is zero") {
    try expectEqual(AudioRecorder.computeRMS([]), 0)
}

test("RMS of single sample") {
    try expectNear(AudioRecorder.computeRMS([1.0]), 1.0, accuracy: 0.001)
}

test("Louder signal has higher RMS") {
    let rmsQuiet = AudioRecorder.computeRMS([Float](repeating: 0.1, count: 1000))
    let rmsLoud = AudioRecorder.computeRMS([Float](repeating: 0.8, count: 1000))
    try expect(rmsLoud > rmsQuiet, "Loud RMS should be > quiet RMS")
}

// ───────────────────────────────────────────────────────────────────────
// OutputManager Clipboard Tests
// ───────────────────────────────────────────────────────────────────────

print("\n📋 OutputManager Clipboard")

test("Copy to clipboard stores text") {
    let text = "Test clipboard \(UUID().uuidString)"
    OutputManager.copyToClipboard(text)
    let result = NSPasteboard.general.string(forType: .string)
    try expectEqual(result ?? "", text)
}

test("Copy empty string") {
    OutputManager.copyToClipboard("")
    try expectEqual(NSPasteboard.general.string(forType: .string) ?? "", "")
}

test("Copy Unicode text including emoji") {
    let text = "Příliš žluťoučký kůň 🐴"
    OutputManager.copyToClipboard(text)
    try expectEqual(NSPasteboard.general.string(forType: .string) ?? "", text)
}

test("Copy overwrites previous clipboard") {
    OutputManager.copyToClipboard("first")
    OutputManager.copyToClipboard("second")
    try expectEqual(NSPasteboard.general.string(forType: .string) ?? "", "second")
}

// ───────────────────────────────────────────────────────────────────────
// ConfigManager File I/O Tests
// ───────────────────────────────────────────────────────────────────────

print("\n💾 ConfigManager File I/O")

test("Save and load preserves config") {
    let original = ConfigManager.load()

    var cfg = AppConfig()
    cfg.language = "cs"
    cfg.modelSize = "medium"
    cfg.silenceTimeout = 5.0
    ConfigManager.save(cfg)

    let loaded = ConfigManager.load()
    try expectEqual(loaded.language, "cs")
    try expectEqual(loaded.modelSize, "medium")
    try expectEqual(loaded.silenceTimeout, 5.0)

    // Restore
    ConfigManager.save(original)
}

test("Load returns valid config") {
    let cfg = ConfigManager.load()
    try expect(!cfg.language.isEmpty, "Language should not be empty")
    try expect(!cfg.hotkey.isEmpty, "Hotkey should not be empty")
}

// ───────────────────────────────────────────────────────────────────────
// Summary
// ───────────────────────────────────────────────────────────────────────

print("\n" + String(repeating: "─", count: 50))
print("Results: \(passedTests)/\(totalTests) passed")

if !failedTests.isEmpty {
    print("\n❌ FAILURES:")
    for (name, error) in failedTests {
        print("  • \(name): \(error)")
    }
    print("")
    exit(1)
} else {
    print("✅ All tests passed!\n")
    exit(0)
}
