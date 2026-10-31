#!/usr/bin/env bash
# Host-side. Applies the current dev.yaml to the existing VM by restarting it,
# without a rebuild: the disk, clones and logins survive. See README
# "Applying a dev.yaml change without a rebuild".
#
# A restart alone is not enough: Lima boots from the instance's own copy,
# ~/.lima/<name>/lima.yaml, taken from dev.yaml when the VM was created.
set -euo pipefail

VM_NAME="${VM_NAME:-dev}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

say() { printf '\n==> %s\n' "$*"; }

# Run inside the VM, this would stop the machine it is running on.
command -v limactl >/dev/null || { echo "Run this on the host, not in the VM (no limactl)." >&2; exit 1; }

say "Pulling the latest dev.yaml"
git -C "$HERE" pull --ff-only

say "Stopping VM '$VM_NAME'"
# Drop the shared SSH connection too, or the desktop app and Gateway can stay
# on a stale control master after the restart (see README).
ssh -O exit "lima-${VM_NAME}" 2>/dev/null || true
limactl stop "$VM_NAME"

say "Replacing ~/.lima/$VM_NAME/lima.yaml with dev.yaml"
cp "$HERE/dev.yaml" "$HOME/.lima/$VM_NAME/lima.yaml"

# Starts the VM (provision runs on boot) and rewrites the ~/.ssh/config block,
# whose port changed with the restart.
"$HERE/bootstrap.sh"

# Best-effort provision steps warn with a leading "! " rather than failing the
# boot, so a skipped skill or plugin is easy to miss. Show this boot's warnings.
say "Provision warnings from this boot"
limactl shell "$VM_NAME" -- sudo journalctl -b --no-pager -o cat -t cloud-init 2>/dev/null \
  | grep '^! ' || echo "(none)"
