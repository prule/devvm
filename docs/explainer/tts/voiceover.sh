#!/usr/bin/env bash
# Generate the YouTube voiceover from ../youtube-script.md.
# Creates a project-local venv on first run. All arguments go to voiceover.py:
#   ./voiceover.sh                       # Piper, local and free
#   ./voiceover.sh --dry-run             # just the spoken text and word counts
#   ./voiceover.sh --only electron       # one section
#   ./voiceover.sh --engine openai --voice onyx
#   ./voiceover.sh --engine elevenlabs --voice <your voice id>
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -x .venv/bin/python ]; then
  python3 -m venv .venv
  .venv/bin/pip install -q -r requirements.txt
fi

exec .venv/bin/python voiceover.py "$@"
