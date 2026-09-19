#!/usr/bin/env bash
# Run INSIDE the VM. Migrates one repo off dev containers.
#
#   ./migrate-repo.sh homefleet
#
# Does the mechanical part of steps 6 in the strategy doc. It does NOT commit
# and does NOT push — review the diff, run the tests, then commit yourself. A
# repo that won't build on the pinned Node is information, not a failure of
# this script.
set -euo pipefail

REPO="${1:?usage: migrate-repo.sh <repo-name> [github-owner]}"
OWNER="${2:-prule}"
NODE_VERSION="26.7.0"
DIR="$HOME/projects/$REPO"

say() { printf '\n==> %s\n' "$*"; }

# --- Clone, don't copy --------------------------------------------------------
# Cloning rather than copying from the host guarantees nothing but tracked files
# crosses over: no host node_modules with darwin-arm64 binaries, no .DS_Store,
# no stale .env.
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

# --- Bind dev servers to 0.0.0.0 ----------------------------------------------
# Lima only auto-forwards guest ports bound to 0.0.0.0. dev.yaml declares
# explicit rules for the known ports too, but this is the robust fix.
if [ -f vite.config.ts ] || [ -f vite.config.js ]; then
  grep -q 'host:' vite.config.* 2>/dev/null \
    || say "REMINDER: add \`server: { host: true }\` to vite.config.* so the host browser can reach it"
fi

# --- Install ------------------------------------------------------------------
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
