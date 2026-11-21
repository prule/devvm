#!/bin/bash
# USER: wire ways 2 and 3 into the home directory. Never replaces a
# pre-commit hook a repo already has (lefthook, the pre-commit framework,
# one written by hand); it names those instead, as they are not scanned.
set -uo pipefail
# Way 3: a sourcing line, not a copy, so the user's own lines in
# init.sh survive and a changed husky-init.sh applies at once.
init="$HOME/.config/husky/init.sh"
mkdir -p "$(dirname "$init")"
touch "$init"
grep -q 'devvm/husky-init.sh' "$init" \
  || echo '. /usr/local/share/devvm/husky-init.sh' >> "$init"

# Way 2: every repo under ~/projects. -type d skips worktrees, whose
# .git is a file: they share their main repo's hooks.
find "$HOME/projects" -maxdepth 4 -name .git -type d -prune 2>/dev/null | while read -r gitdir; do
  repo="$(dirname "$gitdir")"
  # Husky (or another hooks dir) is set: .git/hooks is ignored there.
  [ -n "$(git -C "$repo" config --local core.hooksPath 2>/dev/null)" ] && continue
  hook="$gitdir/hooks/pre-commit"
  if [ ! -e "$hook" ]; then
    mkdir -p "$gitdir/hooks"
    install -m 755 /usr/local/share/devvm/git-template/hooks/pre-commit "$hook"
  elif ! grep -q 'devvm-secret-scan' "$hook"; then
    echo "! ${repo#$HOME/}: has its own pre-commit hook, so commits there are NOT scanned for secrets"
  fi
done
