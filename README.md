# TranscriptWhatYouHear

> Native macOS menu bar app that records your voice, transcribes it locally with Whisper (no cloud), and pastes the text into any app. Hotkey-driven, private by design, Apple Silicon optimized. Built with Claude.

---

## Quick Start

1. The mic icon appears in your menu bar when the app is running.
2. Press **⌃⌥Space** to start recording — the icon turns red.
3. Speak naturally. Press **⌃⌥Space** again to stop (or wait for silence auto-stop).
4. Your words are transcribed and pasted into the focused window automatically.

---

## Installation

**Requirements:** macOS 13+, Xcode Command Line Tools (`xcode-select --install`)

```bash
git clone https://github.com/drabepet/TranscriptWhatYouHear.git
cd TranscriptWhatYouHear
./create_app.sh
open ~/Applications/TranscriptWhatYouHear.app
```

`create_app.sh` compiles the Swift source, then packages the binary into a `.app` bundle in `~/Applications`. The Whisper model (~460 MB for `small`) is downloaded automatically on first launch.

To start automatically on login: **System Settings → General → Login Items → (+) → TranscriptWhatYouHear.app**

---

## Required Permissions

Grant in **System Settings → Privacy & Security**:

| Permission | Purpose |
|---|---|
| Microphone | Captures audio while recording |
| Accessibility | Sends Cmd+V (paste) and keystrokes to the focused app after transcription |

---

## Recording Settings

### Mode

- **Toggle** — press the hotkey once to start, press again to stop. Great for longer dictation.
- **Push to talk** — hold the hotkey while speaking; release to stop. Works like a walkie-talkie.

### Language

Choose between **English** and **Czech**. Telling Whisper which language to expect improves speed and accuracy.

### Model

Larger models are more accurate but use more memory and take longer to transcribe. All processing happens locally — nothing is sent to the cloud. Models are downloaded once on first use.

| Model | Disk | RAM | Quality |
|---|---|---|---|
| tiny | ~75 MB | ~125 MB | Decent |
| base | ~145 MB | ~200 MB | Good |
| **small** | **~460 MB** | **~500 MB** | **Better — default** |
| medium | ~1.5 GB | ~1.5 GB | Very good |
| large-v3 | ~3 GB | ~3 GB | Near-human |

### Silence Auto-stop

Recording stops automatically after silence (5 s / 10 s / 20 s / 30 s). Set to **Off** to stop manually.

Use **Calibrate noise…** to tune the silence detector for your environment.

### Max Duration

Hard limit on a single recording (1 / 2 / 5 / 10 min / Unlimited). Protects against accidentally leaving the mic on.

### Post-process Text

When enabled: removes filler words (*um, uh, like, basically, ehm, jako…*), collapses spaces, capitalizes the first letter.

---

## Output Settings

| Mode | Description |
|---|---|
| **Paste (Cmd+V)** | Copies text to clipboard, then simulates Cmd+V. Recommended. |
| **Type (keystroke)** | Types character by character. For apps that block pasting. |
| **Clipboard only** | Clipboard only — paste manually with Cmd+V. |

**Auto-submit** — presses Return after pasting (useful in chat apps).
**Streaming paste** — text appears segment by segment as Whisper processes.

---

## Hotkey

Default: **⌃⌥Space** (Control + Option + Space). To change:

1. Click **Set shortcut…** in the menu.
2. Click **OK**, then press your new key combination within 8 seconds.

---

## Recent Transcriptions

The last 5 transcriptions are saved in the **Recent transcriptions** submenu. Click any entry to copy it to the clipboard.

---

## Files & Logs

| File | Location |
|---|---|
| Log | `~/Library/Logs/TranscriptWhatYouHear.log` |
| Config | `~/Library/Application Support/TranscriptWhatYouHear/config.json` |
| Models | `~/Library/Application Support/TranscriptWhatYouHear/models/` |

---

## Tech Stack

| Component | Library |
|---|---|
| Language | Swift (native macOS) |
| Menu bar UI | AppKit (NSStatusItem) |
| Transcription | [whisper.cpp](https://github.com/ggerganov/whisper.cpp) |
| Audio capture | AVAudioEngine |
| Global hotkey | [HotKey](https://github.com/soffes/HotKey) (Carbon) |
| Paste/Type | CoreGraphics (CGEvent) |

---

## License

MIT

---

*Built with [Claude](https://claude.ai)*
