#!/bin/bash
set -uo pipefail
# Replaced by betterleaks; drop the binary earlier boots installed.
rm -f /usr/local/bin/gitleaks
if [ "$(betterleaks version 2>/dev/null || echo none)" != "${PARAM_BETTERLEAKS_VERSION}" ]; then
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/betterleaks.tar.gz" \
    "https://github.com/betterleaks/betterleaks/releases/download/v${PARAM_BETTERLEAKS_VERSION}/betterleaks_${PARAM_BETTERLEAKS_VERSION}_linux_arm64.tar.gz" \
    && tar -xzf "$tmp/betterleaks.tar.gz" -C "$tmp" betterleaks \
    && install -m 0755 "$tmp/betterleaks" /usr/local/bin/betterleaks \
    || echo "! betterleaks skipped — commits are NOT scanned for secrets until ./update-vm.sh succeeds"
  rm -rf "$tmp"
fi
git config --system init.templateDir /usr/local/share/devvm/git-template
