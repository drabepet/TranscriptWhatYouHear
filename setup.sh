#!/usr/bin/env bash
# setup.sh — one-time setup for Voice Claude
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV="$SCRIPT_DIR/.venv"

echo "╔══════════════════════════════════════╗"
echo "║       Voice Claude — Setup           ║"
echo "╚══════════════════════════════════════╝"
echo

# ── 1. Check Python ───────────────────────────────────────────────────────────
if ! command -v python3 &>/dev/null; then
    echo "❌  python3 not found. Install it from https://python.org or via Homebrew:"
    echo "    brew install python"
    exit 1
fi

PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
echo "✅  Python $PYTHON_VERSION found"

# ── 2. Check / install PortAudio (needed by sounddevice) ─────────────────────
if ! brew list portaudio &>/dev/null 2>&1; then
    echo "📦  Installing PortAudio via Homebrew (required for audio capture)…"
    if ! command -v brew &>/dev/null; then
        echo "❌  Homebrew not found. Install it from https://brew.sh, then re-run this script."
        exit 1
    fi
    brew install portaudio
else
    echo "✅  PortAudio already installed"
fi

# ── 3. Create virtual environment ─────────────────────────────────────────────
if [ ! -d "$VENV" ]; then
    echo "🔧  Creating virtual environment at .venv …"
    python3 -m venv "$VENV"
else
    echo "✅  Virtual environment already exists"
fi

# ── 4. Install Python dependencies ───────────────────────────────────────────
echo "📦  Installing Python dependencies…"
"$VENV/bin/pip" install --upgrade pip -q
"$VENV/bin/pip" install -r "$SCRIPT_DIR/requirements.txt"

echo
echo "✅  All dependencies installed."
echo
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  IMPORTANT: Grant these permissions in                               ║"
echo "║  System Settings → Privacy & Security                                ║"
echo "║                                                                      ║"
echo "║  • Microphone   → Terminal (or your terminal app)                    ║"
echo "║  • Accessibility → Terminal (or your terminal app)                   ║"
echo "║                                                                      ║"
echo "║  Without Accessibility permission the hotkey ⌘⇧Space won't work.    ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo
echo "▶  To start Voice Claude, run:"
echo "   ./run.sh"
echo
echo "   Or run manually:"
echo "   source .venv/bin/activate && python voice_claude.py"
