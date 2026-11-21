#!/bin/bash
# SYSTEM: Hugo, for pauls-blog. The upstream .deb, not Ubuntu's package,
# which lags far behind. Since 0.170 the standard build has everything the
# extended one had (the two tarballs are identical) and there is no
# hugo_extended .deb for arm64 any more, so this installs the standard one
# and checks only the version. The version comes from the blog's deploy
# workflow (see HUGO_VERSION under param:), so a Renovate bump merged in
# pauls-blog reaches the VM on its next boot. Reinstalled only when that
# version changes. Own step and best-effort, so a failed download cannot
# take the rest of the boot with it.
set -uo pipefail
# Same login-user lookup as the first step.
LOGIN_USER="$(awk -F: '$3>=500 && $3<65000 && $6 ~ /^\/home\// {print $1; exit}' /etc/passwd)"
LOGIN_HOME="$(getent passwd "$LOGIN_USER" | cut -d: -f6)"
# The version the blog deploys with, from whatever its checkout has; the
# param only until the blog is cloned. blog-serve reads it the same way.
hugo_v="$(sed -nE 's/^[[:space:]]*HUGO_VERSION:[[:space:]]*"?([0-9][0-9.]*)"?.*/\1/p' \
  "$LOGIN_HOME/projects/current/pauls-blog/.github/workflows/hugo.yml" 2>/dev/null | head -1)"
hugo_v="${hugo_v:-$PARAM_HUGO_VERSION}"
if ! hugo version 2>/dev/null | grep -q "v${hugo_v}-"; then
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/hugo.deb" \
    "https://github.com/gohugoio/hugo/releases/download/v${hugo_v}/hugo_${hugo_v}_linux-arm64.deb" \
    && dpkg -i "$tmp/hugo.deb" \
    || echo "! hugo skipped — re-run ./update-vm.sh later"
  rm -rf "$tmp"
fi

# --- Live preview of pauls-blog, always running ---------------------------
# `blog-serve` (files/bin/blog-serve) under systemd, so the blog with drafts is at
# http://localhost:1313/pauls-blog/ on the Mac whenever the VM is up.
# Restart=always rather than on-failure: before the blog is cloned the
# script exits, and this keeps retrying until the checkout appears,
# without needing another boot. LOGIN_USER is from the top of this step.
printf '%s\n' \
  '[Unit]' \
  'Description=Hugo dev server for pauls-blog (drafts, live reload)' \
  'After=network.target' \
  '[Service]' \
  "User=$LOGIN_USER" \
  'ExecStart=/usr/local/bin/blog-serve' \
  'Restart=always' \
  'RestartSec=30' \
  '[Install]' \
  'WantedBy=multi-user.target' \
  > /etc/systemd/system/devvm-blog.service
systemctl daemon-reload
systemctl enable devvm-blog.service
# restart, not start: picks up a new Hugo or a changed blog-serve on
# ./update-vm.sh, where the service may already be running.
systemctl restart devvm-blog.service || echo "! devvm-blog did not start — see: systemctl status devvm-blog"
