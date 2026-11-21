#!/bin/bash
# SYSTEM: hadolint, for the Dockerfile rule above (shellcheck comes from
# apt). Best-effort, like betterleaks.
set -uo pipefail
if [ "$(hadolint --version 2>/dev/null | grep -o '[0-9][0-9.]*' | head -1)" != "${PARAM_HADOLINT_VERSION}" ]; then
  curl -fsSL -o /tmp/hadolint \
    "https://github.com/hadolint/hadolint/releases/download/v${PARAM_HADOLINT_VERSION}/hadolint-linux-arm64" \
    && install -m 0755 /tmp/hadolint /usr/local/bin/hadolint \
    || echo "! hadolint skipped — re-run ./update-vm.sh"
  rm -f /tmp/hadolint
fi
