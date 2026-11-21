#!/bin/bash
# USER: VS Code over Remote-SSH, for Java (devvm README, VS Code → Java).
#
# First, two keys in the VM's remote settings. java.configuration.runtimes,
# built from JAVA_VERSIONS so it can't drift from the installed JDKs. And
# remote.autoForwardPorts false: Lima already forwards the VM's ports, and
# VS Code's own forwards took Mac ports Lima needed (it held 8000, so
# http://<name>.devvm:8000 hung). Only these keys are rewritten on each
# boot; other settings survive. jq can't parse JSON with
# comments, so a commented settings file is left alone with a warning.
#
# Then the extensions. They install through the VS Code server, which the
# Mac's VS Code downloads into the VM on its first connect, so a fresh VM
# has none and this part waits for a later boot. lru.json lists the servers
# most recently used first. An installed extension is left for VS Code to
# update, as it does by itself. Best-effort throughout.
set -uo pipefail
settings="$HOME/.vscode-server/data/Machine/settings.json"
mkdir -p "$(dirname "$settings")"
[ -s "$settings" ] || echo '{}' > "$settings"
runtimes='[]'
for v in ${PARAM_JAVA_VERSIONS}; do
  is_default=false
  [ "$v" = "${PARAM_JAVA_DEFAULT}" ] && is_default=true
  runtimes="$(jq -c --arg n "JavaSE-${v%%.*}" --arg p "$HOME/.sdkman/candidates/java/$v" --argjson d "$is_default" \
    '. + [{name: $n, path: $p} + (if $d then {default: true} else {} end)]' <<< "$runtimes")"
done
tmp="$(mktemp)"
if jq --argjson r "$runtimes" '."java.configuration.runtimes" = $r | ."remote.autoForwardPorts" = false' "$settings" > "$tmp" 2>/dev/null; then
  mv "$tmp" "$settings"
else
  rm -f "$tmp"
  echo "! VS Code JDK settings not updated — $settings is not plain JSON (comments?). Set java.configuration.runtimes by hand (devvm README, VS Code → Java)"
fi

extensions='vscjava.vscode-java-pack'
servers="$HOME/.vscode-server/cli/servers"
server="$(jq -r '.[0] // empty' "$servers/lru.json" 2>/dev/null)"
cs="$servers/$server/server/bin/code-server"
if [ -z "$server" ] || [ ! -x "$cs" ]; then
  echo "VS Code extensions: no VS Code server in the VM yet; they install on the first boot after VS Code connects"
  exit 0
fi
installed="$("$cs" --list-extensions 2>/dev/null)"
for ext in $extensions; do
  grep -qix "$ext" <<< "$installed" && continue
  timeout 300s "$cs" --install-extension "$ext" < /dev/null > /dev/null \
    || echo "! VS Code extension $ext not installed — install it from VS Code while connected to lima-dev"
done
