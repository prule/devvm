#!/bin/bash
set -euo pipefail
mkdir -p "$HOME/.claude"
install -m 644 /usr/local/share/devvm/CLAUDE.md "$HOME/.claude/CLAUDE.md"
