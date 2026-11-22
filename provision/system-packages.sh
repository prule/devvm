#!/bin/bash
# SYSTEM: root-owned packages.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# The login user is NOT uid 1000: Lima carries the host's uid into the
# guest (501 on macOS), and the home directory is <name>.guest. Lima 2.x
# also warns against referencing LIMA_CIDATA_*, so identify the user by
# scanning /etc/passwd for the first non-system account under /home.
# Defined first because Docker, /etc/environment and the VNC display
# below all need it, and under `set -u` a missing definition aborts.
LOGIN_USER="$(awk -F: '$3>=500 && $3<65000 && $6 ~ /^\/home\// {print $1; exit}' /etc/passwd)"
LOGIN_HOME="$(getent passwd "$LOGIN_USER" | cut -d: -f6)"
[ -n "$LOGIN_USER" ] && [ -d "$LOGIN_HOME" ] \
  || { echo "could not identify the login user" >&2; exit 1; }

apt-get update

# python3-venv: project-local virtualenvs (e.g. docs/explainer/tts uses
# one for Piper). Ubuntu's python3 ships without ensurepip.
# pipx: Python CLIs (mkdocs) in their own venvs, since Ubuntu's python3
# refuses a global `pip install` (PEP 668).
# asciidoctor + ruby-rouge: pauls-blog's .adoc posts, which Hugo renders
# by running asciidoctor (rouge is their `:source-highlighter:`).
# ruby-asciidoctor-pdf: its CV's generate-pdf.sh.
apt-get install -y --no-install-recommends \
  ca-certificates curl git gnupg zip unzip zsh ripgrep jq less \
  build-essential python3-venv pipx shellcheck \
  asciidoctor ruby-rouge ruby-asciidoctor-pdf

# --- Postgres client ----------------------------------------------------
# psql is how the migration scripts run raw SQL against the shared
# Supabase instance (the Supabase CLI's own migration up/db push stop
# working once a database is shared across apps' migration histories),
# and how agents query the dev database below.
# From the PostgreSQL project's apt repo, not Ubuntu's: noble ships 16,
# and a client older than the server is the broken direction — pg_dump
# refuses a newer server outright. A newer client handles every older
# server, Supabase's included. Major taken from POSTGRES_VERSION, so the
# client and the dev database move together.
install -d -m 755 /etc/apt/keyrings
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
  | gpg --batch --yes --dearmor -o /etc/apt/keyrings/pgdg.gpg
echo "deb [arch=arm64 signed-by=/etc/apt/keyrings/pgdg.gpg] https://apt.postgresql.org/pub/repos/apt $(. /etc/os-release && echo "$VERSION_CODENAME")-pgdg main" \
  > /etc/apt/sources.list.d/pgdg.list
apt-get update
apt-get install -y --no-install-recommends "postgresql-client-${PARAM_POSTGRES_VERSION%%.*}"

# --- Electron -----------------------------------------------------------
# Electron apps run their unit tests INSIDE Electron, plus Playwright e2e
# against a packaged build — so Electron has to launch here, not merely
# compile.
#   xvfb      : a virtual display; there is no real one in this VM
#   fakeroot  : electron-builder needs it for Linux (deb) targets
# Playwright's own --with-deps covers some of these, but only some, and
# it is a best-effort step — do not rely on it for Electron.
apt-get install -y --no-install-recommends \
  libgtk-3-0t64 libnotify4 libnss3 libxss1 libxtst6 xdg-utils \
  libatspi2.0-0t64 libdrm2 libgbm1 libasound2t64 libcups2t64 \
  libpango-1.0-0 libcairo2 libx11-xcb1 libxcomposite1 libxdamage1 \
  libxrandr2 libxkbcommon0 xvfb fakeroot

# Ubuntu 23.10+ restricts unprivileged user namespaces through AppArmor,
# which breaks Chromium's and Electron's sandbox: the launch aborts with
# "The SUID sandbox helper binary was found, but is not configured
# correctly ... chrome-sandbox is owned by root and has mode 4755".
#
# Allowing unprivileged userns fixes it with the sandbox left ON. The
# alternatives are worse: --no-sandbox disables a real security boundary,
# and chown/chmod of chrome-sandbox has to be redone after every
# node_modules install. Guarded, since the knob only exists on 23.10+.
if [ -e /proc/sys/kernel/apparmor_restrict_unprivileged_userns ]; then
  echo 'kernel.apparmor_restrict_unprivileged_userns = 0' \
    > /etc/sysctl.d/61-electron-userns.conf
  sysctl -p /etc/sysctl.d/61-electron-userns.conf
fi

# --- A display you can look at ------------------------------------------
# xvfb-run gives tests a throwaway display nobody can see. To actually
# watch an Electron app, a persistent Xvfb runs on :99 and x11vnc serves
# it; macOS Screen Sharing connects via vnc://localhost:5901.
#   :99   : clear of xvfb-run -a, which counts up from :99 only if taken
#           — it is, so test runs land on :100+ and never on this screen
#   5901  : not 5900, which the Mac's own Screen Sharing server owns
#   -localhost : reachable only through Lima's forward (see portForwards)
# DISPLAY is deliberately NOT set machine-wide: with DISPLAY set and no
# tty, ssh (so git over ssh) reaches for an X askpass helper. Opt in per
# command with DISPLAY=:99.
#
# No window manager, so windows have no title bars and cannot be moved;
# fine for looking at one app. The password is a random 8 characters
# (the VNC limit) in ~/.vnc/password.txt — it is Screen Sharing that
# insists on one, and -localhost is the real boundary.
apt-get install -y --no-install-recommends x11vnc
vnc_dir="$LOGIN_HOME/.vnc"
if [ ! -s "$vnc_dir/passwd" ]; then
  install -d -m 0700 -o "$LOGIN_USER" -g "$LOGIN_USER" "$vnc_dir"
  pw="$(head -c 64 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 8)"
  printf '%s\n' "$pw" > "$vnc_dir/password.txt"
  x11vnc -storepasswd "$pw" "$vnc_dir/passwd"
  chown "$LOGIN_USER:$LOGIN_USER" "$vnc_dir/password.txt" "$vnc_dir/passwd"
  chmod 0600 "$vnc_dir/password.txt" "$vnc_dir/passwd"
fi
printf '%s\n' \
  "SET client_min_messages = warning;" \
  '[Unit]' \
  'Description=Persistent X display :99 for viewing GUI apps' \
  '[Service]' \
  "User=$LOGIN_USER" \
  'ExecStart=/usr/bin/Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp' \
  'Restart=on-failure' \
  '[Install]' \
  'WantedBy=multi-user.target' \
  > /etc/systemd/system/devvm-display.service
printf '%s\n' \
  "SET client_min_messages = warning;" \
  '[Unit]' \
  'Description=VNC server for display :99' \
  'BindsTo=devvm-display.service' \
  'After=devvm-display.service' \
  '[Service]' \
  "User=$LOGIN_USER" \
  "ExecStart=/usr/bin/x11vnc -display :99 -rfbport 5901 -localhost -noipv6 -rfbportv6 -1 -forever -shared -rfbauth $vnc_dir/passwd" \
  'Restart=on-failure' \
  'RestartSec=2' \
  '[Install]' \
  'WantedBy=multi-user.target' \
  > /etc/systemd/system/devvm-vnc.service
systemctl daemon-reload
systemctl enable --now devvm-display.service devvm-vnc.service

# --- JetBrains remote backend prerequisites -----------------------------
# Gateway downloads and runs the WebStorm backend itself (into
# ~/.cache/JetBrains), so there is nothing to install for the IDE as
# such. Two things it does need from the OS:
#
# 1. A handful of X/font libraries. JetBrains' own docs say the backend
#    is self-contained and needs no extra dependencies, but their Alpine
#    requirements list these explicitly and headless Debian images are
#    routinely missing them. ~20MB of insurance against a backend that
#    starts and then dies on a missing libXext.
apt-get install -y --no-install-recommends \
  libxext6 libxrender1 libxtst6 libxi6 libfreetype6 fontconfig procps

# 2. More inotify watches. The default is far too low for an IDE indexing
#    forty repos; past the limit the IntelliJ platform silently gives up
#    on file watching and falls back to recursive directory scans, which
#    is the "why is my IDE constantly re-scanning" symptom. 524288 is
#    JetBrains' own recommendation.
# printf, not a heredoc: a heredoc body and terminator have to sit at
# column 0, which inside this YAML block scalar is impossible — the
# terminator ends up indented, bash never recognises it, and the rest of
# the script gets swallowed into the file. `bash -n` does NOT catch it.
printf 'fs.inotify.max_user_watches = %s\nfs.inotify.max_user_instances = %s\n' \
  524288 512 > /etc/sysctl.d/60-jetbrains-inotify.conf
sysctl -p /etc/sysctl.d/60-jetbrains-inotify.conf

# GONE: Eclipse Temurin from the Adoptium apt repo, and with it the
# `jdkDistro: tem` devcontainer-Feature workaround. JVM versions are
# SDKMAN's job now (provision/sdkman.sh) — `zip` above is its one
# extra dependency, and omitting it is what made the first attempt fail.

# --- Docker Engine, native ---------------------------------------------
# Not Docker Desktop: no licence question, no 47GB VM-inside-a-VM, and
# containers run directly on this kernel. This is where
# the local Supabase stack runs.
# --batch --yes: on a re-provision the keyring already exists, and without
# them gpg asks to overwrite it on a TTY provision doesn't have — which
# aborts this whole script under `set -e`.
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=arm64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update

apt-get install -y --no-install-recommends \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

usermod -aG docker "$LOGIN_USER"
systemctl enable --now docker

# --- SonarQube Community Build ------------------------------------------
# Code-quality gate for every repo, scanned with `sonar-check` (files/bin/sonar-check).
# Its embedded Elasticsearch refuses to start below this map count.
printf 'vm.max_map_count = %s\n' 524288 > /etc/sysctl.d/62-sonarqube.conf
sysctl -p /etc/sysctl.d/62-sonarqube.conf
# Created once; `unless-stopped` brings it back at boot, and leaves it
# down after a `docker stop sonarqube`.
# shortcut: embedded H2 database, which SonarQube cannot upgrade in place —
# fine while a version bump means a VM rebuild; move to Postgres if not.
# Anonymous read access, so agents can query issues with a plain curl; the
# server is only on 127.0.0.1 and scans still need the token.
docker inspect sonarqube > /dev/null 2>&1 \
  || docker run -d --name sonarqube --restart unless-stopped \
    -p 127.0.0.1:9000:9000 \
    -e SONAR_FORCEAUTHENTICATION=false \
    -v sonarqube_data:/opt/sonarqube/data \
    -v sonarqube_extensions:/opt/sonarqube/extensions \
    -v sonarqube_logs:/opt/sonarqube/logs \
    "sonarqube:${PARAM_SONARQUBE_VERSION}"

# Scanner CLI, with its own bundled JRE so it ignores SDKMAN's java.
scanner="/opt/sonar-scanner-${PARAM_SONAR_SCANNER_VERSION}-linux-aarch64"
if [ ! -x "$scanner/bin/sonar-scanner" ]; then
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/scanner.zip" \
    "https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${PARAM_SONAR_SCANNER_VERSION}-linux-aarch64.zip"
  unzip -q "$tmp/scanner.zip" -d /opt
  rm -rf "$tmp"
fi
ln -sfn "$scanner/bin/sonar-scanner" /usr/local/bin/sonar-scanner

# --- Postgres: the dev database -----------------------------------------
# A local database agents can query while they code, separate from the
# Supabase stack (54322). Two login roles, so exploring cannot change
# anything:
#   dev_ro  reads every table in every database (pg_read_all_data), and
#           its sessions start read-only on top of that
#   dev_rw  owns the `dev` database and may create more; run migrations
#           as this one
# Passwords are generated once and kept in /etc/devdb (root only). Every
# boot re-applies them, the roles and the grants, so a re-provision and a
# fresh volume both end in the same state.
install -d -m 700 /etc/devdb
for role in postgres dev_ro dev_rw; do
  [ -s "/etc/devdb/$role" ] || (umask 077; openssl rand -hex 24 > "/etc/devdb/$role")
done
# The volume is mounted at /var/lib/postgresql, not .../data: from 18 on
# the image keeps its data in a per-major subdirectory there.
docker inspect postgres > /dev/null 2>&1 \
  || docker run -d --name postgres --restart unless-stopped \
    -p 127.0.0.1:5432:5432 \
    -e POSTGRES_PASSWORD="$(cat /etc/devdb/postgres)" \
    -v postgres_data:/var/lib/postgresql \
    "postgres:${PARAM_POSTGRES_VERSION}"
docker start postgres > /dev/null
# Wait over TCP, not the socket: on first start the image runs a
# socket-only server to initialise, then restarts. Statements sent to
# that one would be cut off by the restart.
timeout 120s bash -c 'until docker exec postgres pg_isready -q -h 127.0.0.1 -U postgres; do sleep 2; done'
# Through stdin, not -c: psql expands :'var' only in input it reads.
printf '%s\n' \
  "SET client_min_messages = warning;" \
  "SELECT 'CREATE ROLE dev_rw' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'dev_rw') \gexec" \
  "SELECT 'CREATE ROLE dev_ro' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'dev_ro') \gexec" \
  "ALTER ROLE dev_rw LOGIN CREATEDB PASSWORD :'rw_pw';" \
  "ALTER ROLE dev_ro LOGIN PASSWORD :'ro_pw';" \
  "ALTER ROLE dev_ro SET default_transaction_read_only = on;" \
  "GRANT pg_read_all_data TO dev_ro;" \
  "SELECT 'CREATE DATABASE dev OWNER dev_rw' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'dev') \gexec" \
  | docker exec -i postgres psql -q -U postgres -d postgres -v ON_ERROR_STOP=1 \
      -v rw_pw="$(cat /etc/devdb/dev_rw)" -v ro_pw="$(cat /etc/devdb/dev_ro)"
# `psql service=dev_ro` / `service=dev_rw`. Ubuntu's libpq reads services
# from here; passwords go in ~/.pgpass, which is the user's own file, so
# only this database's two lines are replaced.
install -d /etc/postgresql-common
printf '[%s]\nhost=localhost\nport=5432\ndbname=dev\nuser=%s\n\n' \
  dev_ro dev_ro dev_rw dev_rw > /etc/postgresql-common/pg_service.conf
pgpass="$LOGIN_HOME/.pgpass"
touch "$pgpass"
sed -i '/^localhost:5432:\*:dev_r[ow]:/d' "$pgpass"
for role in dev_ro dev_rw; do
  printf 'localhost:5432:*:%s:%s\n' "$role" "$(cat "/etc/devdb/$role")" >> "$pgpass"
done
chown "$LOGIN_USER:" "$pgpass"
chmod 600 "$pgpass"

# --- JAVA_HOME / PATH for non-interactive shells ------------------------
# Points at SDKMAN's `current` symlink, so `sdk default java <v>` moves
# the machine default for scripts too — one place to change it.
#
# The java entry goes LAST in PATH, deliberately. sdkman-init prepends
# its own candidates entry in interactive shells and `sdk use` / `sdk env`
# rewrites that one; a java entry ahead of it wins and silently breaks
# per-project switching (observed: `sdk env` reported 21 while `java
# -version` still said 25). At the tail it only serves non-interactive
# shells, which have no sdk function anyway.
echo "JAVA_HOME=\"$LOGIN_HOME/.sdkman/candidates/java/current\"" >> /etc/environment
printf 'PATH="%s/.fnm/aliases/default/bin:%s/.local/share/pnpm/bin:%s/.fnm:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:%s/.sdkman/candidates/java/current/bin"\n' \
  "$LOGIN_HOME" "$LOGIN_HOME" "$LOGIN_HOME" "$LOGIN_HOME" >> /etc/environment

# --- Supabase CLI -------------------------------------------------------
# Static binary, not a global npm install (which Supabase deprecates).
# Ported from post-create.sh step 3, but installed ONCE for the machine
# instead of once per container.
if [ "$(supabase --version 2>/dev/null || echo none)" != "${PARAM_SUPABASE_CLI_VERSION}" ]; then
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/supabase.tar.gz" \
    "https://github.com/supabase/cli/releases/download/v${PARAM_SUPABASE_CLI_VERSION}/supabase_${PARAM_SUPABASE_CLI_VERSION}_linux_arm64.tar.gz"
  tar -xzf "$tmp/supabase.tar.gz" -C "$tmp" supabase
  install -m 0755 "$tmp/supabase" /usr/local/bin/supabase
  rm -rf "$tmp"
fi

apt-get clean && rm -rf /var/lib/apt/lists/*

# Counteract the sparse-image ratchet where the stack allows it: fstrim
# tells the host which blocks are free again. Ubuntu enables this timer
# by default; making it explicit because it matters more here than usual.
# Whether the freed blocks are actually reclaimed depends on discard
# support through virtio-blk under vz, so treat it as a best effort and
# watch `ls -lks ~/.lima/dev/diffdisk` on the host if the image creeps.
systemctl enable fstrim.timer || true
