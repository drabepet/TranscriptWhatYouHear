import AppKit
import CoreGraphics

public enum OutputManager {
    public static func output(_ text: String, mode: String) {
        switch mode {
        case "type":
            typeText(text)
        case "clipboard":
            copyToClipboard(text)
        default: // "paste"
            paste(text)
        }
        Log.debug("Output [\(mode)] \(text.count) chars")
    }

    public static func paste(_ text: String) {
        // Clipboard must be set on main thread for reliability
        if Thread.isMainThread {
            copyToClipboard(text)
        } else {
            DispatchQueue.main.sync {
                copyToClipboard(text)
            }
        }
        // Delay to let pasteboard settle before simulating Cmd+V
        usleep(100_000)

        // Try CGEvent first, fall back to AppleScript
        if !simulatePasteViaCGEvent() {
            Log.warning("CGEvent paste failed — trying AppleScript fallback")
            simulatePasteViaAppleScript()
        }
    }

    public static func typeText(_ text: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for char in text {
            let str = String(char)
            var utf16 = Array(str.utf16)
            if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                down.post(tap: .cgSessionEventTap)
            }
            if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                up.post(tap: .cgSessionEventTap)
            }
            usleep(5_000)
        }
    }

    public static func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    public static func sendReturn() {
        let source = CGEventSource(stateID: .combinedSessionState)
        if let down = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true) {
            down.post(tap: .cgSessionEventTap)
        }
        usleep(10_000)
        if let up = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false) {
            up.post(tap: .cgSessionEventTap)
        }
    }

    /// Check if the app has Accessibility permissions (needed for CGEvent key simulation).
    public static func checkAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Private

    /// Simulate Cmd+V via CGEvent. Returns true if events were created successfully.
    private static func simulatePasteViaCGEvent() -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else {
            Log.error("Failed to create CGEvent for paste")
            return false
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgSessionEventTap)
        usleep(20_000)
        up.post(tap: .cgSessionEventTap)
        return true
    }

    /// Fallback: simulate Cmd+V via AppleScript / System Events.
    private static func simulatePasteViaAppleScript() {
        let script = NSAppleScript(source: """
            tell application "System Events"
                keystroke "v" using command down
            end tell
        """)
        var errorInfo: NSDictionary?
        script?.executeAndReturnError(&errorInfo)
        if let err = errorInfo {
            Log.error("AppleScript paste failed: \(err)")
        }
    }
}
