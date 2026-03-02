#!/usr/bin/env python3
"""
Voice Claude — macOS menu bar companion for voice-controlling Claude desktop.

Hotkey: configurable (default ⌃⌥Space)

Permissions needed (System Settings → Privacy & Security):
  • Microphone       — audio capture
  • Input Monitoring — global hotkey (pynput)
  • Accessibility    — Cmd+V paste / keystroke (osascript)

Log:    ~/Library/Logs/VoiceClaude.log
Config: <script dir>/config.json
"""

import collections
import json
import logging
import os
import platform
import queue
import re
import subprocess
import tempfile
import threading
import time

import numpy as np
import rumps
import sounddevice as sd
import soundfile as sf
from faster_whisper import WhisperModel

# ── Defaults (overridden by config.json) ───────────────────────────────────────
MODEL_SIZE  = "small"
SAMPLE_RATE = 16_000
HOTKEY      = "<ctrl>+<alt>+<space>"
LOG_PATH    = os.path.expanduser("~/Library/Logs/VoiceClaude.log")
ICON_DIR    = os.path.join(os.path.dirname(os.path.abspath(__file__)), "icons")
CONFIG_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "config.json")
DOCS_PATH   = os.path.join(os.path.dirname(os.path.abspath(__file__)), "docs.html")
HISTORY_SIZE = 5

# ── Lookup tables ──────────────────────────────────────────────────────────────
LANGUAGES = {"English": "en", "Czech": "cs"}

MODES = {
    "Toggle":       "toggle",
    "Push to talk": "push_to_talk",
}

MODELS = {
    # Model       Disk     RAM(int8)
    "tiny":     "tiny",     # ~75 MB  ~125 MB  decent
    "base":     "base",     # ~145 MB ~200 MB  good
    "small":    "small",    # ~461 MB ~500 MB  better  ← default
    "medium":   "medium",   # ~1.5 GB ~1.5 GB  very good
    "large-v3": "large-v3", # ~3 GB   ~3 GB    near-human
}

OUTPUT_MODES = {
    "Paste  (Cmd+V)":    "paste",
    "Type  (keystroke)": "type",
    "Clipboard only":    "clipboard",
}

SILENCE_OPTIONS = {
    "Off":        0.0,
    "5 seconds":  5.0,
    "10 seconds": 10.0,
    "20 seconds": 20.0,
    "30 seconds": 30.0,
}

MAX_OPTIONS = {
    "1 minute":   60.0,
    "2 minutes":  120.0,
    "5 minutes":  300.0,
    "10 minutes": 600.0,
    "Unlimited":  0.0,
}

FILLER_WORDS = frozenset({
    # English
    "um", "uh", "er", "ah", "hmm", "like", "right", "so", "well",
    "okay", "ok", "basically", "literally", "actually", "seriously",
    "you know", "i mean", "kind of", "sort of",
    # Czech
    "ehm", "takže", "vlastně", "prostě", "jako", "jo", "no",
})

DEFAULT_CONFIG: dict = {
    "language":          "en",
    "mode":              "toggle",
    "hotkey":            "<ctrl>+<alt>+<space>",
    "model_size":        "small",
    "silence_timeout":   10.0,
    "silence_threshold": 0.01,
    "max_duration":      600.0,
    "auto_submit":       False,
    "output_mode":       "paste",
    "streaming_paste":   False,
    "post_process":      False,
}

# ── Config ─────────────────────────────────────────────────────────────────────

def load_config() -> dict:
    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, encoding="utf-8") as f:
                return {**DEFAULT_CONFIG, **json.load(f)}
        except Exception:
            pass
    return DEFAULT_CONFIG.copy()


def save_config(cfg: dict) -> None:
    with open(CONFIG_PATH, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2)


# ── Logging ────────────────────────────────────────────────────────────────────

def _setup_logging() -> logging.Logger:
    os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
    fmt = logging.Formatter(
        "%(asctime)s [%(levelname)-8s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    fh = logging.FileHandler(LOG_PATH, encoding="utf-8")
    fh.setFormatter(fmt)
    ch = logging.StreamHandler()
    ch.setFormatter(fmt)
    lg = logging.getLogger("voice_claude")
    lg.setLevel(logging.DEBUG)
    lg.addHandler(fh)
    lg.addHandler(ch)
    return lg


log = _setup_logging()


# ── Icons ──────────────────────────────────────────────────────────────────────

def _build_icons() -> dict[str, str | None]:
    """Generate menu-bar PNGs; skip states whose file already exists."""
    os.makedirs(ICON_DIR, exist_ok=True)
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        log.warning("Pillow not installed — emoji fallback active")
        return {s: None for s in ("idle", "recording", "processing", "error")}

    SIZE = 44

    def mic(draw, fill, lw: int = 3) -> None:
        draw.rounded_rectangle([15, 3, 29, 25], radius=7, fill=fill)
        draw.arc([7, 13, 37, 33], start=0, end=180, fill=fill, width=lw)
        draw.rectangle([20, 33, 24, 39], fill=fill)
        draw.rectangle([13, 39, 31, 42], fill=fill)

    specs = [
        ("idleTemplate.png",       "idle"),
        ("recording.png",          "recording"),
        ("processingTemplate.png", "processing"),
        ("errorTemplate.png",      "error"),
    ]

    icons: dict[str, str] = {}
    for fname, state in specs:
        path = os.path.join(ICON_DIR, fname)
        icons[state] = path
        if os.path.exists(path):
            continue
        img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        d   = ImageDraw.Draw(img)
        if state == "idle":
            mic(d, (0, 0, 0, 255))
        elif state == "recording":
            d.ellipse([4, 4, SIZE - 4, SIZE - 4], fill=(210, 40, 40, 255))
        elif state == "processing":
            mic(d, (130, 130, 130, 255))
        elif state == "error":
            d.rectangle([19, 5, 25, 28], fill=(0, 0, 0, 255))
            d.ellipse([18, 33, 26, 41],  fill=(0, 0, 0, 255))
        img.save(path)
        log.debug("Icon created: %s", path)
    return icons


ICONS = _build_icons()
_EMOJI = {"idle": "🎤", "recording": "🔴", "processing": "⏳", "error": "⚠️"}


# ── Helpers ────────────────────────────────────────────────────────────────────

def _fmt_hotkey(s: str) -> str:
    """Convert pynput hotkey string to a readable symbol string."""
    return (s.replace("<ctrl>", "⌃").replace("<alt>", "⌥")
             .replace("<cmd>", "⌘").replace("<shift>", "⇧")
             .replace("<space>", "Spc").replace("+", ""))


def _label_for(options: dict, value) -> str | None:
    """Return the dict key whose value matches, or None."""
    return next((k for k, v in options.items() if v == value), None)


# ── App ────────────────────────────────────────────────────────────────────────

class VoiceClaudeApp(rumps.App):

    def __init__(self):
        idle_icon = ICONS.get("idle")
        super().__init__(
            "" if idle_icon else _EMOJI["idle"],
            icon=idle_icon,
            quit_button=None,
            template=True,
        )

        self._cfg = load_config()

        # Recording state
        self.recording           = False
        self.audio_data: list    = []
        self.model               = None
        self._speech_detected    = False
        self._last_speech_time   = 0.0
        self._auto_stop          = False
        self._hotkey_active      = False
        self._max_timer: threading.Timer | None = None
        self._rec_start          = 0.0

        # Shortcut capture state
        self._capturing_shortcut  = False
        self._captured_hotkey_str = ""
        self._capture_event       = threading.Event()

        # History
        self._history: collections.deque[str] = collections.deque(maxlen=HISTORY_SIZE)

        # Thread-safe UI update queue — drained on main thread by _drain_timer
        self._ui_queue: queue.SimpleQueue = queue.SimpleQueue()

        # ── Build menus ───────────────────────────────────────────────────────
        self.status_item = rumps.MenuItem("Loading Whisper model…")
        self.status_item.set_callback(None)

        hk_display = _fmt_hotkey(self._cfg.get("hotkey", HOTKEY))
        self.toggle_item = rumps.MenuItem(
            f"⏺  Start recording  {hk_display}", callback=self.on_toggle
        )

        # Choice submenus
        self._lang_menu    = self._build_choice_menu("Language",          LANGUAGES,       self._cfg["language"],        self._set_language)
        self._mode_menu    = self._build_choice_menu("Mode",              MODES,           self._cfg["mode"],            self._set_mode)
        self._model_menu   = self._build_choice_menu("Model",             MODELS,          self._cfg["model_size"],      self._switch_model)
        self._silence_menu = self._build_choice_menu("Silence auto-stop", SILENCE_OPTIONS, self._cfg["silence_timeout"], self._set_silence)
        self._max_menu     = self._build_choice_menu("Max duration",      MAX_OPTIONS,     self._cfg["max_duration"],    self._set_max)

        # Compound submenus
        self._build_opt_items()
        self._rec_menu  = self._build_recording_menu()
        self._out_menu  = self._build_output_submenu()
        self._hist_menu = self._build_history_menu()

        self._shortcut_item = rumps.MenuItem(
            f"Set shortcut…  {hk_display}", callback=self._set_shortcut
        )

        self.menu = [
            self.status_item,
            None,
            self.toggle_item,
            None,
            self._rec_menu,
            self._out_menu,
            None,
            self._shortcut_item,
            None,
            self._hist_menu,
            None,
            rumps.MenuItem("Help…", callback=self._open_help),
            rumps.MenuItem("Open log", callback=self._open_log),
            None,
            rumps.MenuItem("Quit", callback=self.quit_app),
        ]

        # Drain timer — runs on main thread every 50 ms, applies queued UI updates
        self._drain_timer = rumps.Timer(self._drain_ui, 0.05)
        self._drain_timer.start()

        log.info("Starting — model=%s hotkey=%s", self._cfg["model_size"], self._cfg["hotkey"])
        self._setup_hotkey()
        threading.Thread(target=self._load_model, daemon=True).start()

    # ── Thread-safe UI scheduling ─────────────────────────────────────────────

    def _ui(self, fn) -> None:
        """Queue fn() to be called on the main thread by the drain timer."""
        self._ui_queue.put(fn)

    def _drain_ui(self, _timer) -> None:
        """Called on the AppKit main thread every 50 ms — flush UI update queue."""
        try:
            while True:
                fn = self._ui_queue.get_nowait()
                try:
                    fn()
                except Exception as exc:
                    log.debug("UI update error: %s", exc)
        except queue.Empty:
            pass

    # ── Generic choice-menu builder ───────────────────────────────────────────

    def _build_choice_menu(self, title: str, options: dict,
                           current_value, callback) -> rumps.MenuItem:
        menu = rumps.MenuItem(title)
        items: dict[str, rumps.MenuItem] = {}
        for label, value in options.items():
            item = rumps.MenuItem(label, callback=callback)
            item.state = 1 if value == current_value else 0
            items[label] = item
            menu.add(item)
        menu._items = items          # type: ignore[attr-defined]
        menu._options = options      # type: ignore[attr-defined]
        return menu

    def _update_choice_menu(self, menu: rumps.MenuItem, new_value) -> None:
        for label, item in menu._items.items():   # type: ignore[attr-defined]
            item.state = 1 if menu._options[label] == new_value else 0  # type: ignore[attr-defined]

    # ── Submenu builders ──────────────────────────────────────────────────────

    def _build_opt_items(self) -> None:
        self._opt_items: dict[str, rumps.MenuItem] = {}
        for label, key in [
            ("Auto-submit  (Enter after paste)", "auto_submit"),
            ("Streaming paste",                  "streaming_paste"),
            ("Post-process text",                "post_process"),
        ]:
            item = rumps.MenuItem(label, callback=self._toggle_option)
            item.state = 1 if self._cfg.get(key, False) else 0
            self._opt_items[key] = item

    def _build_recording_menu(self) -> rumps.MenuItem:
        menu = rumps.MenuItem("Recording")
        menu.add(self._lang_menu)
        menu.add(self._mode_menu)
        menu.add(self._model_menu)
        self._add_sep(menu)
        menu.add(self._silence_menu)
        menu.add(self._max_menu)
        self._add_sep(menu)
        menu.add(self._opt_items["post_process"])
        menu.add(rumps.MenuItem("Calibrate noise…", callback=self._calibrate_noise))
        return menu

    def _build_output_submenu(self) -> rumps.MenuItem:
        menu = rumps.MenuItem("Output")
        self._out_items: dict[str, rumps.MenuItem] = {}
        for label, code in OUTPUT_MODES.items():
            item = rumps.MenuItem(label, callback=self._set_output)
            item.state = 1 if code == self._cfg["output_mode"] else 0
            self._out_items[label] = item
            menu.add(item)
        self._add_sep(menu)
        menu.add(self._opt_items["auto_submit"])
        menu.add(self._opt_items["streaming_paste"])
        return menu

    @staticmethod
    def _add_sep(menu: rumps.MenuItem) -> None:
        sep = rumps.MenuItem("─────────────────")
        sep.set_callback(None)
        menu.add(sep)

    def _build_history_menu(self) -> rumps.MenuItem:
        menu = rumps.MenuItem("Recent transcriptions")
        placeholder = rumps.MenuItem("(none yet)")
        placeholder.set_callback(None)
        menu.add(placeholder)
        return menu

    # ── Settings callbacks ────────────────────────────────────────────────────

    def _set_language(self, sender: rumps.MenuItem) -> None:
        code = LANGUAGES[sender.title]
        self._cfg["language"] = code
        save_config(self._cfg)
        self._update_choice_menu(self._lang_menu, code)
        log.info("Language → %s (%s)", sender.title, code)

    def _set_mode(self, sender: rumps.MenuItem) -> None:
        code = MODES[sender.title]
        self._cfg["mode"] = code
        save_config(self._cfg)
        self._update_choice_menu(self._mode_menu, code)
        log.info("Mode → %s", code)

    def _switch_model(self, sender: rumps.MenuItem) -> None:
        new_size = MODELS[sender.title]
        if new_size == self._cfg["model_size"]:
            return
        self._cfg["model_size"] = new_size
        save_config(self._cfg)
        self._update_choice_menu(self._model_menu, new_size)
        self.model = None
        self._set_state("processing")
        self.status_item.title = f"Loading Whisper {new_size}…"
        threading.Thread(target=self._load_model, daemon=True).start()
        log.info("Switching model → %s", new_size)

    def _set_output(self, sender: rumps.MenuItem) -> None:
        code = OUTPUT_MODES[sender.title]
        self._cfg["output_mode"] = code
        save_config(self._cfg)
        for label, item in self._out_items.items():
            item.state = 1 if OUTPUT_MODES[label] == code else 0
        log.info("Output mode → %s", code)

    def _set_silence(self, sender: rumps.MenuItem) -> None:
        val = SILENCE_OPTIONS[sender.title]
        self._cfg["silence_timeout"] = val
        save_config(self._cfg)
        self._update_choice_menu(self._silence_menu, val)
        log.info("Silence timeout → %s s", val)

    def _set_max(self, sender: rumps.MenuItem) -> None:
        val = MAX_OPTIONS[sender.title]
        self._cfg["max_duration"] = val
        save_config(self._cfg)
        self._update_choice_menu(self._max_menu, val)
        log.info("Max duration → %s s", val)

    def _toggle_option(self, sender: rumps.MenuItem) -> None:
        for key, item in self._opt_items.items():
            if item is sender:
                self._cfg[key] = not self._cfg.get(key, False)
                sender.state = 1 if self._cfg[key] else 0
                save_config(self._cfg)
                log.info("Option %s → %s", key, self._cfg[key])
                break

    # ── Shortcut capture ──────────────────────────────────────────────────────

    def _set_shortcut(self, _sender) -> None:
        current = _fmt_hotkey(self._cfg.get("hotkey", HOTKEY))
        resp = rumps.alert(
            "Set Shortcut",
            f"Current shortcut: {current}\n\n"
            "Click OK, then press your new key combination\n"
            "(use at least one modifier key + one other key).",
            ok="OK", cancel="Cancel",
        )
        if resp != 1:
            return
        self._captured_hotkey_str = ""
        self._capture_event.clear()
        self._capturing_shortcut = True
        self.status_item.title = "Press your new shortcut now…"
        threading.Thread(target=self._await_shortcut_capture, daemon=True).start()

    def _await_shortcut_capture(self) -> None:
        captured = self._capture_event.wait(timeout=8.0)
        self._capturing_shortcut = False
        if captured and self._captured_hotkey_str:
            self._cfg["hotkey"] = self._captured_hotkey_str
            save_config(self._cfg)
            display = _fmt_hotkey(self._captured_hotkey_str)
            hk_str  = self._captured_hotkey_str

            def _apply(d=display):
                self.toggle_item.title    = f"⏺  Start recording  {d}"
                self._shortcut_item.title = f"Set shortcut…  {d}"
                self._restart_hotkey_listener()
                self._set_ready()
            self._ui(_apply)

            rumps.notification("Voice Claude", "", f"Shortcut set to {display}")
            log.info("Hotkey changed → %s", hk_str)
        else:
            log.warning("Shortcut capture timed out")
            self._ui(self._set_ready)

    # ── Icon / state ──────────────────────────────────────────────────────────

    def _set_state(self, state: str) -> None:
        """Must be called on the main thread (directly or via _ui())."""
        path = ICONS.get(state)
        if path and os.path.exists(path):
            self.template = (state != "recording")
            self.icon  = path
            self.title = ""
        else:
            self.icon  = None
            self.title = _EMOJI.get(state, "")

    # ── Audio beeps ───────────────────────────────────────────────────────────

    @staticmethod
    def _beep(freq: float, duration: float = 0.09) -> None:
        def play():
            t    = np.linspace(0, duration, int(SAMPLE_RATE * duration), False)
            wave = np.sin(2 * np.pi * freq * t) * 0.35
            fade = max(1, len(wave) // 5)
            wave[-fade:] *= np.linspace(1.0, 0.0, fade)
            sd.play(wave.astype(np.float32), SAMPLE_RATE)
            sd.wait()
        threading.Thread(target=play, daemon=True).start()

    # ── Model ─────────────────────────────────────────────────────────────────

    def _load_model(self) -> None:
        size = self._cfg.get("model_size", MODEL_SIZE)
        log.info("Loading Whisper '%s'…", size)
        try:
            params = self._compute_params()
            self.model = WhisperModel(size, **params)
            log.info("Model loaded — warming up…")
            self._warmup_model()
            log.info("Ready")

            def _after_load(s=size):
                self.status_item.title = f"Ready  (Whisper {s})"
                self._set_state("idle")
            self._ui(_after_load)

        except Exception as exc:
            log.exception("Model load failed")

            def _on_err(e=exc):
                self.status_item.title = f"Model error: {e}"
                self._set_state("error")
            self._ui(_on_err)

    @staticmethod
    def _compute_params() -> dict:
        cpu_count = os.cpu_count() or 4
        if platform.machine() == "arm64":
            log.info("Apple Silicon detected — using %d CPU threads", min(cpu_count, 8))
            return {"device": "cpu", "compute_type": "int8",
                    "cpu_threads": min(cpu_count, 8)}
        return {"device": "cpu", "compute_type": "int8",
                "cpu_threads": max(1, cpu_count // 2)}

    def _warmup_model(self) -> None:
        silent = np.zeros(SAMPLE_RATE // 2, dtype=np.float32)
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
            tmp = f.name
        try:
            sf.write(tmp, silent, SAMPLE_RATE)
            list(self.model.transcribe(tmp, language="en")[0])
            log.debug("Warmup complete")
        except Exception:
            log.debug("Warmup skipped")
        finally:
            os.unlink(tmp)

    # ── Hotkey listener ───────────────────────────────────────────────────────

    def _setup_hotkey(self) -> None:
        from pynput import keyboard

        hotkey_str = self._cfg.get("hotkey", HOTKEY)
        try:
            _combo: set = set(keyboard.HotKey.parse(hotkey_str))
        except ValueError:
            log.warning("Invalid hotkey '%s' — using default", hotkey_str)
            hotkey_str = HOTKEY
            _combo = set(keyboard.HotKey.parse(HOTKEY))

        _pressed: set = set()

        def _on_press(key):
            try:
                k = listener.canonical(key)
                _pressed.add(k)

                if self._capturing_shortcut:
                    if len(_pressed) >= 2:
                        parts = []
                        for pk in _pressed:
                            if isinstance(pk, keyboard.Key):
                                parts.append(f"<{pk.name}>")
                            elif hasattr(pk, "char") and pk.char:
                                parts.append(pk.char)
                        if len(parts) >= 2:
                            self._captured_hotkey_str = "+".join(
                                sorted(parts, key=lambda x: (not x.startswith("<"), x))
                            )
                            self._capture_event.set()
                    return

                if _combo.issubset(_pressed) and not self._hotkey_active:
                    self._hotkey_active = True
                    mode = self._cfg["mode"]
                    if mode == "push_to_talk":
                        if not self.recording:
                            self.on_toggle(None)
                    else:
                        self.on_toggle(None)
            except Exception as e:
                log.debug("hotkey press: %s", e)

        def _on_release(key):
            try:
                k = listener.canonical(key)
                _pressed.discard(k)
                if k in _combo:
                    self._hotkey_active = False
                    if self._cfg["mode"] == "push_to_talk" and self.recording:
                        self.on_toggle(None)
            except Exception as e:
                log.debug("hotkey release: %s", e)

        listener = keyboard.Listener(on_press=_on_press, on_release=_on_release)
        listener.daemon = True
        listener.start()
        self._hotkey_listener = listener
        log.info("Hotkey: %s  mode=%s", hotkey_str, self._cfg["mode"])

    def _restart_hotkey_listener(self) -> None:
        if hasattr(self, "_hotkey_listener"):
            self._hotkey_listener.stop()
        self._setup_hotkey()

    # ── Toggle ────────────────────────────────────────────────────────────────

    def on_toggle(self, _sender) -> None:
        if not self.recording:
            self._start_recording()
        else:
            self._stop_recording()

    # ── Recording ─────────────────────────────────────────────────────────────

    def _start_recording(self) -> None:
        if self.model is None:
            rumps.notification("Voice Claude", "", "Model still loading — please wait.")
            return

        self.recording         = True
        self.audio_data        = []
        self._speech_detected  = False
        self._last_speech_time = 0.0
        self._auto_stop        = False
        self._rec_start        = time.monotonic()

        hk = _fmt_hotkey(self._cfg.get("hotkey", HOTKEY))

        def _ui_start(h=hk):
            self._set_state("recording")
            self.toggle_item.title = f"⏹  Stop recording  {h}"
        self._ui(_ui_start)

        max_s = self._cfg["max_duration"]
        if max_s > 0:
            self._max_timer = threading.Timer(max_s, self._on_max_duration)
            self._max_timer.daemon = True
            self._max_timer.start()

        self._beep(880)
        log.info("Recording started (silence=%.0fs  max=%s)",
                 self._cfg["silence_timeout"], f"{max_s:.0f}s" if max_s else "∞")

        threading.Thread(target=self._record_loop,   daemon=True).start()
        threading.Thread(target=self._timer_loop,    daemon=True).start()

    def _record_loop(self) -> None:
        with sd.InputStream(
            samplerate=SAMPLE_RATE, channels=1, dtype="float32",
            callback=self._audio_callback,
        ):
            while self.recording and not self._auto_stop:
                sd.sleep(50)

        if self._auto_stop and self.recording:
            log.info("Silence auto-stop")
            self._stop_recording()

    def _audio_callback(self, indata, _frames, time_info, _status) -> None:
        if not self.recording:
            return
        self.audio_data.append(indata.copy())

        rms = float(np.sqrt(np.mean(indata ** 2)))
        threshold = self._cfg.get("silence_threshold", 0.01)
        timeout   = self._cfg.get("silence_timeout",   10.0)

        if rms > threshold:
            self._last_speech_time = time_info.currentTime
            self._speech_detected  = True
        elif self._speech_detected and timeout > 0:
            silence = time_info.currentTime - self._last_speech_time
            if silence >= timeout:
                self._auto_stop = True

    def _timer_loop(self) -> None:
        """Update status label with elapsed recording time."""
        while self.recording:
            elapsed = int(time.monotonic() - self._rec_start)
            m, s = divmod(elapsed, 60)
            title = f"● {m}:{s:02d}  — {_fmt_hotkey(self._cfg.get('hotkey', HOTKEY))} to stop"
            self._ui(lambda t=title: setattr(self.status_item, "title", t))
            time.sleep(0.5)

    def _stop_recording(self) -> None:
        if not self.recording:
            return
        self.recording = False

        if self._max_timer:
            self._max_timer.cancel()
            self._max_timer = None

        hk = _fmt_hotkey(self._cfg.get("hotkey", HOTKEY))

        def _ui_stop(h=hk):
            self._set_state("processing")
            self.status_item.title = "Transcribing…"
            self.toggle_item.title = f"⏺  Start recording  {h}"
        self._ui(_ui_stop)

        self._beep(550)
        duration = len(self.audio_data) * 512 / SAMPLE_RATE
        log.info("Recording stopped — ~%.1f s captured", duration)

        threading.Thread(target=self._transcribe_and_paste, daemon=True).start()

    def _on_max_duration(self) -> None:
        log.warning("Max duration reached — auto-stopping")
        self._stop_recording()

    # ── Transcription ─────────────────────────────────────────────────────────

    def _transcribe_and_paste(self) -> None:
        if not self.audio_data:
            log.warning("No audio captured")
            self._ui(lambda: self._set_ready("no audio"))
            return

        audio = np.concatenate(self.audio_data, axis=0).flatten()
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
            tmp = f.name

        try:
            sf.write(tmp, audio, SAMPLE_RATE)
            lang     = self._cfg["language"]
            segments, info = self.model.transcribe(tmp, language=lang)

            log.info("Transcribing — lang=%s", lang)

            streaming = (self._cfg.get("streaming_paste", False)
                         and self._cfg.get("output_mode") != "clipboard")

            if streaming:
                full_parts: list[str] = []
                first = True
                for seg in segments:
                    t = self._post_process(seg.text.strip())
                    if t:
                        self._do_output(("" if first else " ") + t)
                        full_parts.append(t)
                        first = False
                text = " ".join(full_parts)
            else:
                text = self._post_process(
                    " ".join(s.text for s in segments).strip()
                )
                if text:
                    self._do_output(text)

            log.info("Transcribed — lang=%s prob=%.2f text=%r",
                     info.language, info.language_probability, text)

            if text:
                if self._cfg.get("auto_submit") and not streaming:
                    self._send_enter()
                preview = text if len(text) <= 70 else text[:67] + "…"

                def _ui_done(t=text, p=preview):
                    self._add_to_history(t)
                    self.status_item.title = f"Pasted: {p}"
                    self._set_state("idle")
                self._ui(_ui_done)
                self._beep(1100, 0.06)
            else:
                log.warning("No speech detected")
                self._ui(lambda: self._set_ready("no speech detected"))

        except Exception as exc:
            log.exception("Transcription error")

            def _ui_err(e=exc):
                self.status_item.title = f"Error: {e}"
                self._set_state("error")
            self._ui(_ui_err)
        finally:
            os.unlink(tmp)

    # ── Output ────────────────────────────────────────────────────────────────

    def _do_output(self, text: str) -> None:
        mode = self._cfg.get("output_mode", "paste")
        if mode == "clipboard":
            subprocess.run(["pbcopy"], input=text.encode(), check=True)
        elif mode == "type":
            for i in range(0, len(text), 40):
                chunk   = text[i:i + 40]
                escaped = chunk.replace("\\", "\\\\").replace('"', '\\"')
                subprocess.run(
                    ["osascript", "-e",
                     f'tell application "System Events" to keystroke "{escaped}"'],
                    check=True,
                )
        else:  # paste
            subprocess.run(["pbcopy"], input=text.encode(), check=True)
            subprocess.run(
                ["osascript", "-e",
                 'tell application "System Events" to keystroke "v" using command down'],
                check=True,
            )
        log.debug("Output [%s] %d chars", mode, len(text))

    @staticmethod
    def _send_enter() -> None:
        subprocess.run(
            ["osascript", "-e",
             'tell application "System Events" to keystroke return'],
            check=True,
        )

    # ── Post-processing ───────────────────────────────────────────────────────

    def _post_process(self, text: str) -> str:
        if not self._cfg.get("post_process", False) or not text:
            return text
        for fw in sorted(FILLER_WORDS, key=len, reverse=True):
            text = re.sub(r"(?i)\b" + re.escape(fw) + r"\b", "", text)
        text = re.sub(r" {2,}", " ", text).strip()
        if text:
            text = text[0].upper() + text[1:]
        return text

    # ── History ───────────────────────────────────────────────────────────────

    def _add_to_history(self, text: str) -> None:
        """Must be called on the main thread (via _ui)."""
        self._history.appendleft(text)
        for key in list(self._hist_menu.keys()):
            del self._hist_menu[key]
        for i, t in enumerate(self._history, 1):
            preview = f"{i}.  " + (t if len(t) <= 52 else t[:49] + "…")

            def make_cb(full_text):
                def cb(_sender):
                    subprocess.run(["pbcopy"], input=full_text.encode())
                    rumps.notification("Voice Claude", "", "Copied to clipboard.")
                return cb

            self._hist_menu.add(rumps.MenuItem(preview, callback=make_cb(t)))

    # ── Noise calibration ─────────────────────────────────────────────────────

    def _calibrate_noise(self, _sender) -> None:
        resp = rumps.alert(
            "Noise Calibration",
            "Stay quiet for 2 seconds.\nClick Start when ready.",
            ok="Start", cancel="Cancel",
        )
        if resp != 1:
            return
        self.status_item.title = "Calibrating… stay quiet"
        threading.Thread(target=self._do_calibration, daemon=True).start()

    def _do_calibration(self) -> None:
        try:
            recording = sd.rec(int(2 * SAMPLE_RATE), samplerate=SAMPLE_RATE,
                               channels=1, dtype="float32")
            sd.wait()
            rms       = float(np.sqrt(np.mean(recording ** 2)))
            threshold = round(max(rms * 2.0, 0.004), 5)
            self._cfg["silence_threshold"] = threshold
            save_config(self._cfg)

            def _ui_cal(t=threshold):
                self._set_ready(f"threshold set to {t}")
            self._ui(_ui_cal)

            rumps.notification("Voice Claude", "",
                               f"Calibrated. New silence threshold: {threshold}")
            log.info("Calibrated: ambient RMS=%.5f → threshold=%.5f", rms, threshold)
        except Exception as exc:
            log.exception("Calibration failed")

            def _ui_cal_err(e=exc):
                self.status_item.title = f"Calibration error: {e}"
            self._ui(_ui_cal_err)

    # ── Help ──────────────────────────────────────────────────────────────────

    def _open_help(self, _sender) -> None:
        subprocess.run(["open", DOCS_PATH])

    # ── Helpers ───────────────────────────────────────────────────────────────

    def _set_ready(self, note: str = "") -> None:
        """Must be called on the main thread (directly or via _ui)."""
        self._set_state("idle")
        size   = self._cfg.get("model_size", MODEL_SIZE)
        suffix = f"  ({note})" if note else ""
        self.status_item.title = f"Ready  (Whisper {size}){suffix}"

    def _open_log(self, _sender) -> None:
        subprocess.run(["open", LOG_PATH])

    def quit_app(self, _sender) -> None:
        log.info("Quitting")
        rumps.quit_application()


# ── Entry point ────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    VoiceClaudeApp().run()
