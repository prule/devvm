#!/usr/bin/env bash
# Run INSIDE the VM. Migrates one repo off dev containers.
#
#   ./migrate-repo.sh my-repo [github-owner]
#
# github-owner defaults to the account gh is logged in as.
#
# Does NOT commit and does NOT push. Review the diff, run the tests, then commit
# yourself. A repo that won't build on the pinned Node is information, not a
# failure of this script.
set -euo pipefail

REPO="${1:?usage: migrate-repo.sh <repo-name> [github-owner]}"
OWNER="${2:-$(gh api user --jq .login 2>/dev/null || true)}"
[ -n "$OWNER" ] || { echo "no github-owner given and gh is not logged in" >&2; exit 1; }
NODE_VERSION="26.7.0"
DIR="$HOME/projects/current/$REPO"

say() { printf '\n==> %s\n' "$*"; }

# --- Clone, don't copy --------------------------------------------------------
# Cloning rather than copying from the host guarantees only tracked files cross
# over: no macOS-built node_modules, no .DS_Store, no stale .env. The host copy
# stays where it is until the VM is proven.
if [ ! -d "$DIR" ]; then
  say "Cloning $OWNER/$REPO"
  git clone "git@github.com:$OWNER/$REPO.git" "$DIR"
fi
cd "$DIR"

# --- Drop the container config ------------------------------------------------
if [ -d .devcontainer ]; then
  say "Removing .devcontainer/"
  git rm -r --quiet .devcontainer
fi
for doc in docs/DevContainers.md DevContainers.md; do
  [ -f "$doc" ] && { say "Removing $doc"; git rm --quiet "$doc"; }
done

# --- Pin to the one Node version ----------------------------------------------
for f in .node-version .nvmrc; do
  if [ -f "$f" ]; then
    old="$(tr -d '[:space:]' < "$f")"
    if [ "$old" != "$NODE_VERSION" ]; then
      say "Node pin: $old -> $NODE_VERSION ($f)"
      echo "$NODE_VERSION" > "$f"
    fi
  fi
done

# --- IDE config out of the repo -----------------------------------------------
# The WebStorm backend writes .idea/ into the project, inside the VM.
for pat in .idea/; do
  if [ -f .gitignore ] && ! grep -qxF "$pat" .gitignore; then
    say "Adding $pat to .gitignore"
    echo "$pat" >> .gitignore
  fi
done

# --- Bind dev servers to 0.0.0.0 ----------------------------------------------
if ls vite.config.* >/dev/null 2>&1; then
  grep -q 'host:' vite.config.* 2>/dev/null \
    || say "REMINDER: add \`server: { host: true }\` to vite.config.* so the host browser can reach it"
fi

# --- Install ------------------------------------------------------------------
# Native local disk, so this is as fast as it was on a container volume — and
# faster than it would have been across a shared mount.
if [ -f package.json ]; then
  say "Installing dependencies"
  if [ -f pnpm-lock.yaml ]; then CI=true pnpm install --frozen-lockfile; else CI=true pnpm install; fi

  if [ -d node_modules/@playwright ] || [ -d node_modules/playwright ]; then
    say "Playwright browsers"
    pnpm exec playwright install chromium || say "  ! skipped"
  fi
fi

say "Migrated. Now: run the tests, check the diff, then commit."
git status --short
