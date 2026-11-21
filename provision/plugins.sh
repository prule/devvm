#!/bin/bash
# USER: Claude Code plugins, user-level. First declare the marketplace and
# enable the plugin in ~/.claude/settings.json, which needs no CLI. autoUpdate
# makes Claude Code check the marketplace for a newer plugin version at each
# start (off by default for third-party marketplaces). Merged with jq so
# other settings survive. Enabling alone does NOT install a plugin: a
# session does not install one that is enabled but missing.
#
# So when a CLI exists (~/.local/bin/claude, or the desktop app's
# ~/.claude/remote/ccd-cli/<version>), each boot also adds a missing
# marketplace, installs a missing plugin, and updates an installed one to
# its latest version. claude-cli.sh, an earlier step, is best-effort, so it may not.
# Failures (no network, no GitHub key yet) do not fail the boot.
set -euo pipefail
settings="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"
[ -s "$settings" ] || echo '{}' > "$settings"

# "<marketplace name> <github owner/repo> <plugin name>", one per line.
plugins='
sdlc-pipeline prule/sdlc-pipeline sdlc-pipeline
ponytail DietrichGebert/ponytail ponytail
'
echo "$plugins" | while read -r market repo plugin; do
  [ -n "$market" ] || continue
  tmp="$(mktemp)"
  jq --arg m "$market" --arg r "$repo" --arg p "$plugin@$market" '
    .extraKnownMarketplaces[$m] = {source: {source: "github", repo: $r}, autoUpdate: true}
    | .enabledPlugins[$p] = true
  ' "$settings" > "$tmp" && mv "$tmp" "$settings"
done

claude="$(command -v claude || command -v "$HOME/.local/bin/claude" || ls -d "$HOME"/.claude/remote/ccd-cli/* 2>/dev/null | sort -V | tail -1 || true)"
[ -n "$claude" ] || exit 0
# A plugin added to the list above is in settings.json but not installed
# yet, and `plugin update` fails on it ("Marketplace not found"), so add
# and install whatever is missing first, then update.
known="$HOME/.claude/plugins/known_marketplaces.json"
installed="$HOME/.claude/plugins/installed_plugins.json"
echo "$plugins" | while read -r market repo plugin; do
  [ -n "$market" ] || continue
  if ! jq -e --arg m "$market" 'has($m)' "$known" > /dev/null 2>&1; then
    timeout 180s "$claude" plugin marketplace add "$repo" < /dev/null \
      || { echo "! marketplace $market not added — run '$claude plugin marketplace add $repo' later"; continue; }
  fi
  if ! jq -e --arg p "$plugin@$market" '.plugins | has($p)' "$installed" > /dev/null 2>&1; then
    timeout 180s "$claude" plugin install "$plugin@$market" --scope user < /dev/null \
      || echo "! plugin $plugin not installed — run '$claude plugin install $plugin@$market' later"
    continue
  fi
  timeout 180s "$claude" plugin marketplace update "$market" < /dev/null \
    && timeout 180s "$claude" plugin update "$plugin@$market" --scope user < /dev/null \
    || echo "! plugin $plugin not updated — run '$claude plugin update $plugin@$market' later"
done
