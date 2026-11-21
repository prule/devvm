#!/bin/bash
# USER: graphify, the CLI in its own pipx venv (as mkdocs below), then its
# Claude Code skill. `graphify install` copies the skill to
# ~/.claude/skills/graphify and appends a "# graphify" block to
# ~/.claude/CLAUDE.md. claude-md.sh, the step before this one in dev.yaml, rewrites that file on every boot, so
# this step must come after it and runs `graphify install` on every boot;
# it is local and idempotent. It adds no hooks: those are per repo, with
# `graphify install --project` or `graphify hook install`, a repo's choice.
# Reinstalled only when the pinned version changes. Best-effort.
set -uo pipefail
want="graphifyy ${PARAM_GRAPHIFY_VERSION}"
if [ "$(pipx list --short 2>/dev/null | grep '^graphifyy ')" != "$want" ]; then
  pipx install --force "graphifyy==${PARAM_GRAPHIFY_VERSION}" \
    || echo "! graphify skipped — run 'pipx install graphifyy' later"
fi
if [ -x "$HOME/.local/bin/graphify" ]; then
  "$HOME/.local/bin/graphify" install > /dev/null < /dev/null \
    || echo "! graphify skill not installed — run 'graphify install' later"
fi
