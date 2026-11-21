#!/bin/bash
# USER: Claude Code skills, user-level, so every repo in the VM gets them.
# Best-effort, like Playwright: a GitHub hiccup must not fail the provision.
#
# `-a claude-code` alone makes the CLI COPY into ~/.claude/skills rather than
# symlink from ~/.agents/skills as it does on the host for multiple agents.
# Only Claude Code runs here, so the copy is the simpler layout.
set -uo pipefail
export FNM_DIR="$HOME/.fnm"
# Deterministic path, not `eval "$(fnm env)"` — see the toolchain step.
export PATH="$FNM_DIR/aliases/default/bin:$HOME/.local/share/pnpm/bin:$FNM_DIR:$PATH"

# "<github owner/repo> <skill name> [only]", one per line. Every skill
# in the repo is installed, and the name is only the "already there?"
# sentinel, unless the line ends in `only`: then just that one skill.
# caveman is `only` because its repo holds two dozen skills, and as a
# skill, not the plugin: the plugin's SessionStart hook turns caveman
# mode on in every session, where the skill waits for /caveman, as on
# the Mac.
skills='
danyuchn/asd-ste100-skill asd-ste100
mattpocock/skills setup-matt-pocock-skills
prule/project-setup vssw-audit-project-compliance
JuliusBrussee/caveman caveman only
'
echo "$skills" | while read -r repo name only; do
  [ -n "$repo" ] || continue
  [ -f "$HOME/.claude/skills/$name/SKILL.md" ] && continue
  pick=()
  [ "$only" = only ] && pick=(--skill "$name")
  npx --yes "skills@${PARAM_SKILLS_CLI_VERSION}" add "$repo" ${pick[@]+"${pick[@]}"} -g -a claude-code -y < /dev/null \
    || echo "! skill $name skipped — run 'npx skills add $repo ${pick[*]+${pick[*]}} -g -a claude-code' later"
done

# Then bring every installed skill to its latest version, as the plugin
# step does for plugins. `add` records each skill's source and folder
# hash in ~/.agents/.skill-lock.json, copies included; `update` compares
# those hashes with GitHub and re-copies only the changed skills.
# It overwrites local edits to a skill.
timeout 300s npx --yes "skills@${PARAM_SKILLS_CLI_VERSION}" update -g -y < /dev/null \
  || echo "! skills not updated — run 'npx skills update -g -y' later"
