#!/bin/bash
# USER: SDKMAN + the JVM versions. Separate step so a slow JDK download
# cannot take the JS toolchain down with it.
set -euo pipefail

export SDKMAN_DIR="$HOME/.sdkman"

# rcupdate=false: the installer would otherwise append its own init to
# the rc files, and the shell wiring is written in one place below.
if [ ! -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]; then
  curl -fsSL "https://get.sdkman.io?rcupdate=false" | bash
fi

# sdkman-init trips `set -u`, so relax it just for the source.
set +u
source "$SDKMAN_DIR/bin/sdkman-init.sh"
set -u

# Non-interactive: answer the "set as default?" prompt from stdin.
for v in ${PARAM_JAVA_VERSIONS}; do
  if [ ! -d "$SDKMAN_DIR/candidates/java/$v" ]; then
    sdk install java "$v" < /dev/null
  fi
done
# Explicit, because SDKMAN makes the FIRST install its default — which
# would leave interactive shells on 21 while /etc/environment pointed
# non-interactive ones at 25.
sdk default java "${PARAM_JAVA_DEFAULT}" < /dev/null

# `cd` into a directory holding .sdkmanrc switches the JDK. Interactive
# shells only — it hooks PROMPT_COMMAND, so scripts never see it. For
# non-interactive correctness Gradle toolchains are the mechanism, and
# they find every version above in SDKMAN's candidates directory.
sed -i 's/^sdkman_auto_env=false/sdkman_auto_env=true/' "$SDKMAN_DIR/etc/config"

for shell in bash zsh; do
  rc="$HOME/.${shell}rc"
  touch "$rc"
  grep -q 'sdkman-init' "$rc" && continue
  {
    echo ''
    echo '# --- sdkman (JVM versions) ---'
    echo '# Last on purpose: sdkman-init prepends its candidates to PATH.'
    echo 'export SDKMAN_DIR="$HOME/.sdkman"'
    echo '[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ] && source "$SDKMAN_DIR/bin/sdkman-init.sh"'
  } >> "$rc"
done
