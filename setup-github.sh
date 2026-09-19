#!/usr/bin/env bash
# Run ONCE inside the VM. Interactive, so it can't live in dev.yaml's provision.
#
#   limactl copy setup-github.sh dev:/tmp/ && limactl shell dev -- bash /tmp/setup-github.sh
#
# Creates a VM-only SSH key. Deliberately NOT the host's key and deliberately
# not agent forwarding: this identity is individually revocable, and nothing in
# the VM can ever sign with the host's keys.
set -euo pipefail

KEY="$HOME/.ssh/id_ed25519"

if [ ! -f "$KEY" ]; then
  echo "==> Generating VM-only key"
  ssh-keygen -t ed25519 -C "lima-dev-vm" -f "$KEY" -N ""
else
  echo "==> Key already exists: $KEY"
fi

if ! command -v gh >/dev/null; then
  echo "==> Installing gh"
  (type -p wget >/dev/null || sudo apt-get install -y wget)
  sudo mkdir -p -m 755 /etc/apt/keyrings
  wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt-get update && sudo apt-get install -y gh
fi

# Say yes when it offers to upload the public key above.
gh auth status >/dev/null 2>&1 || gh auth login --git-protocol ssh --hostname github.com

git config --global user.name  "$(gh api user  --jq .name  2>/dev/null || echo prule)"
git config --global user.email "$(gh api user  --jq .email 2>/dev/null || echo '')"
git config --global init.defaultBranch main

echo
echo "==> Verifying GitHub SSH"
ssh -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 | head -2 || true
echo
echo "==> Done. Now log in to Claude Code (it installs itself on first"
echo "    desktop-app SSH connection, or run 'claude' here)."
