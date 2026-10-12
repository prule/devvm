#!/usr/bin/env bash
# Run INSIDE the VM. Migrates one repo off dev containers.
#
#   ./migrate-repo.sh homefleet
#
# The repo already exists — it lives on the host at ~/projects/current and is
# shared into the VM, so there is nothing to clone. This drops the container
# config, pins Node, and reinstalls dependencies for Linux.
#
# Does NOT commit and does NOT push. Review the diff, run the tests, then commit
# yourself. A repo that won't build on the pinned Node is information, not a
# failure of this script.
set -euo pipefail

REPO="${1:?usage: migrate-repo.sh <repo-name>}"
NODE_VERSION="26.7.0"
DIR="/Users/paulrule/projects/current/$REPO"

say() { printf '\n==> %s\n' "$*"; }

[ -d "$DIR" ] || { echo "no such repo on the shared mount: $DIR" >&2; exit 1; }
cd "$DIR"

# --- The platform-binary hazard -----------------------------------------------
# This is the one thing the shared mount reintroduces that the dev containers
# deliberately prevented. Each container kept node_modules on its own volume so
# a Linux container could never inherit a macOS-built native binary. Now the
# directory is shared, so whichever OS ran `pnpm install` last owns the
# binaries: esbuild, rollup, better-sqlite3, sharp and friends are all
# platform-specific.
#
# Rule from here on: pnpm runs in the VM ONLY. Never on the host.
#
# Blowing node_modules away is the only safe move, since the existing tree was
# built by macOS.
if [ -d node_modules ]; then
  say "Removing macOS-built node_modules (pnpm runs in the VM from now on)"
  rm -rf node_modules
fi

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

# --- Keep macOS cruft out of the repo -----------------------------------------
# The host writes .DS_Store into shared folders; WebStorm writes .idea/.
for pat in .DS_Store .idea/; do
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
# Slower than it was in a container: node_modules now lands on virtiofs rather
# than a native volume. This is the accepted cost of host-native WebStorm.
if [ -f package.json ]; then
  say "Installing dependencies (Linux binaries, onto the shared mount)"
  if [ -f pnpm-lock.yaml ]; then CI=true pnpm install --frozen-lockfile; else CI=true pnpm install; fi

  if [ -d node_modules/@playwright ] || [ -d node_modules/playwright ]; then
    say "Playwright browsers"
    pnpm exec playwright install chromium || say "  ! skipped"
  fi
fi

say "Migrated. Now: run the tests, check the diff, then commit."
git status --short
