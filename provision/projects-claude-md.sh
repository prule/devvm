#!/bin/bash
set -euo pipefail
mkdir -p "$HOME/projects"
install -m 644 /usr/local/share/devvm/projects-CLAUDE.md "$HOME/projects/CLAUDE.md"
# The apply-project-standards skill (files/skills/apply-project-standards). Not in the skills CLI's
# lock file, so `skills update` leaves it alone.
mkdir -p "$HOME/.claude/skills/apply-project-standards"
install -m 644 /usr/local/share/devvm/skills/apply-project-standards/SKILL.md \
  "$HOME/.claude/skills/apply-project-standards/SKILL.md"
