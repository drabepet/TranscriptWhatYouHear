#!/usr/bin/env bash
# run.sh — launch TranscriptWhatYouHear
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV="$SCRIPT_DIR/.venv"

if [ ! -d "$VENV" ]; then
    echo "Virtual environment not found. Run ./setup.sh first."
    exit 1
fi

exec "$VENV/bin/python" "$SCRIPT_DIR/voice_claude.py"
