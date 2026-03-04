import AppKit
import Carbon
import HotKey

/// Manages global hotkey registration and shortcut capture.
final class HotkeyManager {
    private var hotKey: HotKey?
    private var globalMonitor: Any?

    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    /// Register a hotkey from config string like "ctrl+option+space".
    func register(shortcut: String) {
        hotKey = nil  // Unregister old

        let (key, modifiers) = Self.parse(shortcut)
        guard let key = key else {
            Log.warning("Could not parse hotkey: \(shortcut)")
            return
        }

        let hk = HotKey(key: key, modifiers: modifiers)
        hk.keyDownHandler = { [weak self] in self?.onKeyDown?() }
        hk.keyUpHandler = { [weak self] in self?.onKeyUp?() }
        hotKey = hk
        Log.info("Hotkey registered: \(shortcut)")
    }

    func unregister() {
        hotKey = nil
    }

    /// Capture the next key combination pressed. Calls back with the shortcut string.
    func captureShortcut(timeout: TimeInterval = 8.0, completion: @escaping (String?) -> Void) {
        // Temporarily unregister current hotkey
        let savedHotKey = hotKey
        hotKey = nil

        var captured = false

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard !captured else { return }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Require at least one modifier
            guard !mods.isEmpty else { return }

            captured = true
            if let monitor = self?.globalMonitor {
                NSEvent.removeMonitor(monitor)
                self?.globalMonitor = nil
            }

            let shortcutStr = Self.encode(keyCode: event.keyCode, modifiers: mods)
            // Restore hotkey
            self?.hotKey = savedHotKey
            completion(shortcutStr)
        }

        // Timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard !captured else { return }
            captured = true
            if let monitor = self?.globalMonitor {
                NSEvent.removeMonitor(monitor)
                self?.globalMonitor = nil
            }
            self?.hotKey = savedHotKey
            completion(nil)
        }
    }

    // MARK: - Display

    static func displayString(for shortcut: String) -> String {
        let parts = shortcut.lowercased().split(separator: "+").map(String.init)
        var symbols: [String] = []
        for part in parts {
            switch part.trimmingCharacters(in: .whitespaces) {
            case "ctrl", "control": symbols.append("⌃")
            case "option", "alt": symbols.append("⌥")
            case "cmd", "command": symbols.append("⌘")
            case "shift": symbols.append("⇧")
            case "space": symbols.append("Spc")
            default: symbols.append(part.trimmingCharacters(in: .whitespaces).capitalized)
            }
        }
        return symbols.joined()
    }

    // MARK: - Parse / Encode

    static func parse(_ shortcut: String) -> (Key?, NSEvent.ModifierFlags) {
        let parts = shortcut.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        var mods: NSEvent.ModifierFlags = []
        var keyPart: String?

        for part in parts {
            switch part {
            case "ctrl", "control": mods.insert(.control)
            case "alt", "option": mods.insert(.option)
            case "cmd", "command": mods.insert(.command)
            case "shift": mods.insert(.shift)
            default: keyPart = part
            }
        }

        guard let kp = keyPart else { return (nil, mods) }
        let key: Key? = keyFromString(kp)
        return (key, mods)
    }

    static func encode(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("option") }
        if modifiers.contains(.command) { parts.append("cmd") }
        if modifiers.contains(.shift) { parts.append("shift") }
        parts.append(stringFromKeyCode(keyCode))
        return parts.joined(separator: "+")
    }

    private static func keyFromString(_ s: String) -> Key? {
        switch s {
        case "space": return .space
        case "return", "enter": return .return
        case "tab": return .tab
        case "escape", "esc": return .escape
        case "delete", "backspace": return .delete
        case "up": return .upArrow
        case "down": return .downArrow
        case "left": return .leftArrow
        case "right": return .rightArrow
        case "a": return .a; case "b": return .b; case "c": return .c
        case "d": return .d; case "e": return .e; case "f": return .f
        case "g": return .g; case "h": return .h; case "i": return .i
        case "j": return .j; case "k": return .k; case "l": return .l
        case "m": return .m; case "n": return .n; case "o": return .o
        case "p": return .p; case "q": return .q; case "r": return .r
        case "s": return .s; case "t": return .t; case "u": return .u
        case "v": return .v; case "w": return .w; case "x": return .x
        case "y": return .y; case "z": return .z
        case "0": return .zero; case "1": return .one; case "2": return .two
        case "3": return .three; case "4": return .four; case "5": return .five
        case "6": return .six; case "7": return .seven; case "8": return .eight
        case "9": return .nine
        case "f1": return .f1; case "f2": return .f2; case "f3": return .f3
        case "f4": return .f4; case "f5": return .f5; case "f6": return .f6
        case "f7": return .f7; case "f8": return .f8; case "f9": return .f9
        case "f10": return .f10; case "f11": return .f11; case "f12": return .f12
        default: return nil
        }
    }

    private static func stringFromKeyCode(_ keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "space"
        case kVK_Return: return "return"
        case kVK_Tab: return "tab"
        case kVK_Escape: return "escape"
        case kVK_Delete: return "delete"
        case kVK_ANSI_A: return "a"; case kVK_ANSI_B: return "b"
        case kVK_ANSI_C: return "c"; case kVK_ANSI_D: return "d"
        case kVK_ANSI_E: return "e"; case kVK_ANSI_F: return "f"
        case kVK_ANSI_G: return "g"; case kVK_ANSI_H: return "h"
        case kVK_ANSI_I: return "i"; case kVK_ANSI_J: return "j"
        case kVK_ANSI_K: return "k"; case kVK_ANSI_L: return "l"
        case kVK_ANSI_M: return "m"; case kVK_ANSI_N: return "n"
        case kVK_ANSI_O: return "o"; case kVK_ANSI_P: return "p"
        case kVK_ANSI_Q: return "q"; case kVK_ANSI_R: return "r"
        case kVK_ANSI_S: return "s"; case kVK_ANSI_T: return "t"
        case kVK_ANSI_U: return "u"; case kVK_ANSI_V: return "v"
        case kVK_ANSI_W: return "w"; case kVK_ANSI_X: return "x"
        case kVK_ANSI_Y: return "y"; case kVK_ANSI_Z: return "z"
        case kVK_ANSI_0: return "0"; case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"; case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"; case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"; case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"; case kVK_ANSI_9: return "9"
        case kVK_F1: return "f1"; case kVK_F2: return "f2"
        case kVK_F3: return "f3"; case kVK_F4: return "f4"
        case kVK_F5: return "f5"; case kVK_F6: return "f6"
        case kVK_F7: return "f7"; case kVK_F8: return "f8"
        case kVK_F9: return "f9"; case kVK_F10: return "f10"
        case kVK_F11: return "f11"; case kVK_F12: return "f12"
        default: return "key\(keyCode)"
        }
    }
}
