#!/bin/bash
# USER: the JS toolchain, owned by the login user.
#
# GONE, all of it, from post-create.sh:
#   step 1  volume ownership chowns  — no named volumes, no root-owned mounts
#   step 1b ~/.claude.json migration — no CLAUDE_CONFIG_DIR; ~/.claude is just
#           a directory in a home directory that persists because it is a VM
#   step 4  pnpm store-dir + the XDG_CONFIG_HOME/JetBrains double-write — the
#           default store at ~/.local/share/pnpm/store is already shared by
#           every project on this machine, which is all /cache ever wanted
#   step 5  per-repo pnpm install — belongs to the repo, not the environment
set -euo pipefail

export FNM_DIR="$HOME/.fnm"
export PNPM_HOME="$HOME/.local/share/pnpm"
export PATH="$FNM_DIR:$PNPM_HOME/bin:$PATH"

# --- fnm + one Node -----------------------------------------------------
# fnm installs one default Node for every project, and interactive shells
# get --use-on-cd so a repo's .node-version / .nvmrc pin still wins
# inside that repo (see the shell wiring below).
if [ ! -x "$FNM_DIR/fnm" ]; then
  curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir "$FNM_DIR" --skip-shell
fi
"$FNM_DIR/fnm" install "${PARAM_NODE_VERSION}"
"$FNM_DIR/fnm" default "${PARAM_NODE_VERSION}"

# Put node/npm on PATH via the default-alias directory rather than
# `eval "$(fnm env)"`. fnm infers the shell from its parent process, and
# in a provision script there is nothing to infer from: it fails with
# "Can't infer shell!", the eval expands to nothing, and the next line
# that needs npm dies under `set -e` — which is exactly how the first
# build of this VM failed. The alias dir is a plain path and always
# correct. (The original Dockerfile did the same thing with ENV PATH.)
export PATH="$FNM_DIR/aliases/default/bin:$PNPM_HOME/bin:$FNM_DIR:$PATH"

# --- pnpm, standalone ---------------------------------------------------
# Self-contained, not tied to a Node install, so an fnm patch bump won't
# lose it. pnpm v10+ self-manages each repo's `packageManager` field, so
# this single binary transparently serves repos still pinned anywhere from
# 11.5.2 to 12.4.2 — the pins can be normalised later, at leisure.
if [ "$(pnpm --version 2>/dev/null || echo none)" != "${PARAM_PNPM_VERSION}" ]; then
  curl -fsSL https://get.pnpm.io/install.sh \
    | env PNPM_VERSION="${PARAM_PNPM_VERSION}" SHELL=/bin/bash sh -
fi

# --- OpenSpec CLI -------------------------------------------------------
# npm, not pnpm: drops the binary into the fnm Node's bin, already on PATH.
# A machine dev tool, not an app dependency. Use the SCOPED package — the
# bare `openspec` on npm is an empty placeholder.
npm install -g "@fission-ai/openspec@${PARAM_OPENSPEC_VERSION}"

# --- Shell wiring -------------------------------------------------------
# bash AND zsh, same as the Dockerfile did. Built with echo rather than a
# heredoc on purpose: a heredoc body has to sit at column 0, which would
# terminate this YAML block scalar early.
#
# NOT written here, deliberately:
#   PLAYWRIGHT_BROWSERS_PATH / PLAYWRIGHT_SKIP_BROWSER_GC
#     The shared browser volume needed both. Playwright's .links files
#     hold absolute paths into a per-project node_modules volume that
#     sibling containers could not see, so each container decided the
#     others' browsers were orphans and garbage-collected them. One
#     filesystem, all node_modules mutually visible: the paths resolve,
#     validation passes, nothing is collected. Default location is fine.
#   CLAUDE_CONFIG_DIR, GH_CONFIG_DIR
#     Both existed to drag credentials onto a mounted volume. ~/.claude
#     and ~/.config/gh are now just directories in a home directory that
#     persists, which is what they always assumed they were.
for shell in bash zsh; do
  rc="$HOME/.${shell}rc"
  touch "$rc"
  if ! grep -q 'dev vm toolchain' "$rc"; then
    {
      echo ''
      echo '# --- dev vm toolchain ---'
      echo 'export FNM_DIR="$HOME/.fnm"'
      echo 'export PNPM_HOME="$HOME/.local/share/pnpm"'
      echo 'export PATH="$FNM_DIR:$PNPM_HOME/bin:$PATH"'
      echo "eval \"\$(fnm env --use-on-cd --shell ${shell})\""
      echo 'export OPENSPEC_TELEMETRY=0'
      echo ''
      echo '# Layer 4 of the pnpm guard, and the only one that fires before'
      echo '# anything is written. The repo-level guards are a preinstall hook'
      echo '# (bypassed by --ignore-scripts), .gitignore, and a CI check — all of'
      echo '# which catch the mistake after the fact. This catches it first.'
      echo '# Scoped to install-type commands and only where a pnpm lockfile is'
      echo '# present, so `npm install -g` and the genuinely-npm repos still work.'
      echo 'npm() { case "$1" in install|i|ci|add|update) if [ -f pnpm-lock.yaml ]; then printf "%s\n" "pnpm-lock.yaml present - use pnpm, not npm" >&2; return 1; fi ;; esac; command npm "$@"; }'
    } >> "$rc"
  fi
  # rc files written before --use-on-cd was added skip the block above; upgrade them in place.
  sed -i 's/fnm env --shell/fnm env --use-on-cd --shell/' "$rc"
done

# Where the repos get cloned. Mirrors the host layout out of habit, so
# paths read the same in notes and commit messages.
mkdir -p "$HOME/projects/current"
