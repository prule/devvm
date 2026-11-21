#!/bin/bash
# USER: the `claude` CLI, for a shell in the VM (`ssh lima-dev`, Gateway's
# terminal). The desktop app installs its own copy on first connect, but
# under ~/.claude/remote/ccd-cli/<version>, which is not on PATH and changes
# name with every update. This is the native installer: ~/.local/bin/claude,
# self-updating, so it is not pinned in `param:` — the desktop app's copy
# floats too, and the two stay roughly in step.
#
# Ubuntu's ~/.profile adds ~/.local/bin only if it existed at login, and it
# did not on a fresh VM, so the rc files add it explicitly. Own marker, not
# the toolchain block's, so an existing VM picks it up on its next boot.
# Best-effort: a download failure must not fail the boot.
set -uo pipefail
if [ ! -x "$HOME/.local/bin/claude" ]; then
  curl -fsSL https://claude.ai/install.sh | bash \
    || echo "! claude CLI skipped — run 'curl -fsSL https://claude.ai/install.sh | bash' later"
fi

for shell in bash zsh; do
  rc="$HOME/.${shell}rc"
  touch "$rc"
  grep -q 'claude cli' "$rc" && continue
  {
    echo ''
    echo '# --- claude cli ---'
    echo 'export PATH="$HOME/.local/bin:$PATH"'
  } >> "$rc"
done
