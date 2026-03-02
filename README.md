# 🎙️ TranscriptWhatYouHear

> macOS menu bar app that records your voice, transcribes it locally with OpenAI Whisper (no cloud), and pastes the text into any app. Hotkey-driven, private by design, Apple Silicon optimized. Built with Claude.

---

## Quick Start

1. The mic icon appears in your menu bar when the app is running.
2. Press **⌃⌥Space** to start recording — the icon turns red.
3. Speak naturally. Press **⌃⌥Space** again to stop (or wait for silence auto-stop).
4. Your words are transcribed and pasted into the focused window automatically.

---

## Installation

**Requirements:** macOS, Python 3.10+, [Homebrew](https://brew.sh)

```bash
git clone https://github.com/drabepet/TranscriptWhatYouHear.git
cd TranscriptWhatYouHear
./setup.sh
./run.sh
```

To install as a clickable `.app` bundle in `~/Applications`:

```bash
./create_app.sh
```

---

## Required Permissions

Grant all three in **System Settings → Privacy & Security**:

| Permission | Purpose |
|---|---|
| 🎤 Microphone | Captures audio while recording |
| ⌨️ Input Monitoring | Detects the global hotkey even when another app is in focus |
| ♿ Accessibility | Sends Cmd+V (paste) and keystrokes to the focused app after transcription |

---

## Recording Settings

### Mode

- **Toggle** — press the hotkey once to start, press again to stop. Great for longer dictation.
- **Push to talk** — hold the hotkey while speaking; release to stop. Works like a walkie-talkie.

### Language

Choose between **English** and **Czech**. Telling Whisper which language to expect improves speed and accuracy — it won't have to guess.

### Model

Larger models are more accurate but use more memory and take longer to transcribe. All processing happens locally — nothing is sent to the cloud.

| Model | Disk | RAM (int8) | Quality |
|---|---|---|---|
| tiny | ~75 MB | ~125 MB | Decent |
| base | ~145 MB | ~200 MB | Good |
| **small** ★ | **~461 MB** | **~500 MB** | **Better — default** |
| medium | ~1.5 GB | ~1.5 GB | Very good |
| large-v3 | ~3 GB | ~3 GB | Near-human |

The model is downloaded once on first use and cached locally. Switching model triggers a reload.

### Silence Auto-stop

Recording stops automatically after you have been silent for the selected duration (5 s / 10 s / 20 s / 30 s). Set to **Off** to disable and stop manually with the hotkey.

Pair with **Calibrate noise…** to make the silence detector ignore background hum — it measures ambient RMS for 2 seconds and sets the threshold automatically.

### Max Duration

Hard upper limit on a single recording (1 min / 2 min / 5 min / 10 min / Unlimited). When reached, recording stops and transcription begins automatically. Protects against accidentally leaving the mic on.

### Post-process Text

When enabled, the transcribed text is cleaned up before pasting:

- Common filler words are removed (*um, uh, like, basically, ehm, prostě…*)
- Multiple spaces are collapsed into one
- The first letter is capitalised

---

## Output Settings

### Output Mode

| Mode | Description |
|---|---|
| **Paste (Cmd+V)** ✅ | Copies text to clipboard, then simulates ⌘V in the focused app. Fast, works with rich-text apps. Recommended. |
| **Type (keystroke)** | Types text character by character via System Events. Useful in apps that block pasting. Note: Czech diacritics may not type correctly. |
| **Clipboard only** | Puts text in the clipboard without pasting. Paste manually with ⌘V when ready. |

### Auto-submit

After pasting, automatically presses **Return**. Useful in chat apps like Claude where Enter sends the message. Works with Paste mode only.

### Streaming Paste

Text appears segment by segment as Whisper finishes each chunk, rather than waiting for the full transcription. Feels faster for longer recordings. Not available in Clipboard only mode.

---

## Hotkey

The default shortcut is **⌃⌥Space** (Control + Option + Space). To change it:

1. Click **Set shortcut…** in the menu.
2. Click **OK** in the dialog.
3. Press your desired key combination within 8 seconds.

The new shortcut is saved to `config.json` and takes effect immediately.

> **Tip:** Avoid shortcuts already used by macOS (e.g. ⌘Space for Spotlight). ⌃⌥Space is safe on most systems.

---

## Recent Transcriptions

The last 5 transcriptions are saved in the **Recent transcriptions** submenu. Click any entry to copy its full text to the clipboard — useful if you accidentally closed a window before pasting.

---

## Files & Logs

| File | Location |
|---|---|
| Log | `~/Library/Logs/TranscriptWhatYouHear.log` |
| Config | `voice_claude/config.json` |

Open the log from the menu with **Open log**, or in Terminal:

```bash
tail -f ~/Library/Logs/TranscriptWhatYouHear.log
```

All settings are stored as JSON in `config.json`. You can edit it manually — changes take effect on next launch.

---

## Tips & Tricks

- 🔉 **Calibrate first** — run *Calibrate noise…* in your usual environment so auto-stop triggers reliably.
- 🚀 **Warm startup** — the model is warmed up silently on launch so your first transcription isn't slower than the rest.
- 🔒 **Fully private** — no audio or text ever leaves your machine.
- 🍎 **Apple Silicon** — automatically uses up to 8 CPU threads for faster transcription.
- 📱 **Launch at login** — System Settings → General → Login Items → (+) → TranscriptWhatYouHear.app

---

## Tech Stack

| Component | Library |
|---|---|
| Menu bar UI | [rumps](https://github.com/jaredks/rumps) |
| Transcription | [faster-whisper](https://github.com/SYSTRAN/faster-whisper) (CTranslate2 backend) |
| Audio capture | [sounddevice](https://python-sounddevice.readthedocs.io) + PortAudio |
| Global hotkey | [pynput](https://pynput.readthedocs.io) |
| Icon generation | [Pillow](https://pillow.readthedocs.io) |

---

## License

MIT

---

*Built with [Claude](https://claude.ai)*
