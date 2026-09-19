#!/usr/bin/env bash
# Host-side. Creates the VM and wires it to the Claude Code desktop app.
# Idempotent: safe to re-run.
set -euo pipefail

VM_NAME="${VM_NAME:-dev}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISK_NEEDED_GB=60   # not the 120GiB sparse max — just enough headroom to start

say() { printf '\n==> %s\n' "$*"; }

# --- 1. Disk ------------------------------------------------------------------
# The VM disk is sparse, but it still needs somewhere to grow. On this machine
# the space comes from Docker Desktop (~47GB) — quit it and delete its data
# BEFORE creating the VM, not after.
avail_gb=$(df -g / | awk 'NR==2 {print $4}')
say "Free disk: ${avail_gb}GB (want >= ${DISK_NEEDED_GB}GB)"
if [ "$avail_gb" -lt "$DISK_NEEDED_GB" ]; then
  cat >&2 <<MSG
Not enough free disk.

  Docker Desktop's data is the likely culprit. Check it:
    du -sh ~/Library/Containers/com.docker.docker

  Quit Docker Desktop, then delete that directory, then re-run this script.
  Do NOT delete it while the VM migration is unverified if you still have
  containers you care about.
MSG
  exit 1
fi

# --- 2. Lima ------------------------------------------------------------------
command -v limactl >/dev/null || { say "Installing Lima"; brew install lima; }

if limactl list --quiet 2>/dev/null | grep -qx "$VM_NAME"; then
  say "VM '$VM_NAME' exists — starting if stopped"
  limactl start "$VM_NAME"
else
  say "Creating VM '$VM_NAME' (first run pulls the Ubuntu image; several minutes)"
  limactl start "$HERE/dev.yaml" --name="$VM_NAME" --tty=false
fi

# --- 3. SSH config ------------------------------------------------------------
# This is the integration point: it writes a real `lima-dev` Host block, which
# is exactly what the desktop app's SSH connection dialog consumes.
say "Updating ~/.ssh/config"
touch ~/.ssh/config
tmp="$(mktemp)"
# Drop any previous lima-<name> block, then append a fresh one.
awk -v host="lima-${VM_NAME}" '
  $1=="Host" { skip = ($2==host) }
  !skip
' ~/.ssh/config > "$tmp"
limactl show-ssh "$VM_NAME" --format=config >> "$tmp"
# Never let a regenerated block silently enable agent forwarding: the VM has
# its own GitHub key on purpose (see setup-github.sh).
if grep -qi '^[[:space:]]*ForwardAgent[[:space:]]\+yes' "$tmp"; then
  say "WARNING: ForwardAgent yes appeared in ~/.ssh/config — removing"
  sed -i '' '/^[[:space:]]*ForwardAgent[[:space:]]*yes/d' "$tmp"
fi
install -m 600 "$tmp" ~/.ssh/config && rm -f "$tmp"

# --- 4. Time Machine ----------------------------------------------------------
# A 120GB disk image that changes constantly will otherwise be re-backed-up
# forever. Everything that matters is in git.
if ! tmutil isexcluded ~/.lima 2>/dev/null | grep -q '\[Excluded\]'; then
  say "Excluding ~/.lima from Time Machine"
  tmutil addexclusion ~/.lima || say "  (skipped — needs Full Disk Access)"
fi

say "Done."
cat <<MSG

  Next:
    1. Claude Code desktop app -> environment dropdown -> + Add SSH connection
         Name:          dev vm
         SSH Host:      lima-${VM_NAME}
         Port / Key:    leave empty (taken from ~/.ssh/config)
       It installs Claude Code on the VM itself on first connect.

    2. Inside the VM, once:
         limactl shell ${VM_NAME}
         bash /tmp/setup-github.sh     # copy it over first, see README

    3. Sanity check:
         limactl shell ${VM_NAME} -- bash -lc 'node -v; pnpm -v; openspec --version; java -version; docker run --rm hello-world'
MSG
