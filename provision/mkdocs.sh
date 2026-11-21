#!/bin/bash
# USER: MkDocs + Material, so a docs repo's `./run serve` / `./run build`
# works (project-setup's `./run setup` does a global `pip install`, which
# Ubuntu refuses). pipx gives it its own venv; --include-deps exposes the
# `mkdocs` binary, which comes from a dependency, on ~/.local/bin.
# Reinstalled only when the pinned version changes. Best-effort.
set -uo pipefail
want="mkdocs-material ${PARAM_MKDOCS_MATERIAL_VERSION}"
if [ "$(pipx list --short 2>/dev/null | grep '^mkdocs-material ')" != "$want" ]; then
  pipx install --force --include-deps "mkdocs-material==${PARAM_MKDOCS_MATERIAL_VERSION}" \
    || echo "! mkdocs skipped — run 'pipx install --include-deps mkdocs-material' later"
fi
