import Foundation
import os

/// Central logger — writes to ~/Library/Logs/TranscriptWhatYouHear.log and stderr.
public enum Log {
    private static let logPath: String = {
        let dir = NSHomeDirectory() + "/Library/Logs"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir + "/TranscriptWhatYouHear.log"
    }()

    private static let fileHandle: FileHandle? = {
        FileManager.default.createFile(atPath: logPath, contents: nil)
        return FileHandle(forWritingAtPath: logPath)
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private static let lock = NSLock()

    public static func info(_ msg: String) { write("INFO    ", msg) }
    public static func debug(_ msg: String) { write("DEBUG   ", msg) }
    public static func warning(_ msg: String) { write("WARNING ", msg) }
    public static func error(_ msg: String) { write("ERROR   ", msg) }

    private static func write(_ level: String, _ msg: String) {
        let ts = dateFormatter.string(from: Date())
        let line = "\(ts) [\(level)] \(msg)\n"
        lock.lock()
        defer { lock.unlock() }
        if let data = line.data(using: .utf8) {
            fileHandle?.seekToEndOfFile()
            fileHandle?.write(data)
        }
        fputs(line, stderr)
    }
}
