import AppKit
import CoreGraphics

enum OutputManager {
    static func output(_ text: String, mode: String) {
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

    static func paste(_ text: String) {
        copyToClipboard(text)
        // Small delay to let pasteboard settle
        usleep(50_000)
        simulateKeyStroke(keyCode: 0x09, flags: .maskCommand)  // Cmd+V
    }

    static func typeText(_ text: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for char in text {
            let str = String(char)
            var utf16 = Array(str.utf16)
            if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                down.post(tap: .cgAnnotatedSessionEventTap)
            }
            if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                up.post(tap: .cgAnnotatedSessionEventTap)
            }
            usleep(5_000)
        }
    }

    static func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    static func sendReturn() {
        simulateKeyStroke(keyCode: 0x24, flags: [])  // Return key
    }

    private static func simulateKeyStroke(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        if let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            down.flags = flags
            down.post(tap: .cgAnnotatedSessionEventTap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            up.flags = flags
            up.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}
