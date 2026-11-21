#!/bin/bash
# USER: Playwright browsers. Separate step so a flaky download can't take the
# toolchain down with it — best-effort, same as post-create.sh step 6.
set -uo pipefail
export FNM_DIR="$HOME/.fnm"
# Deterministic path, not `eval "$(fnm env)"` — see the note in the
# toolchain step. This step failed the first build for exactly that
# reason: "npx: command not found", so no browsers were installed.
export PATH="$FNM_DIR/aliases/default/bin:$HOME/.local/share/pnpm/bin:$FNM_DIR:$PATH"

sudo env "PATH=$PATH" npx --yes playwright install-deps chromium \
  || echo "! playwright OS deps skipped"
npx --yes playwright install chromium \
  || echo "! playwright chromium skipped — run 'npx playwright install chromium' later"
