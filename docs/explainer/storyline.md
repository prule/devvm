# Storyline (Pyramid Principle)

The blog post, the slide deck and the video script all use this one storyline.
Change it here first, then update the three pieces.

## Governing thought

**Run Claude Code in one Linux VM on your Mac, and drive it from the Claude
desktop app over SSH.** The agent gets a full, rebuildable machine that is
separate from your Mac. PWAs and Electron apps run in the VM from start to
finish. Only native macOS builds go back to the host, and only git crosses
the boundary.

## SCQA introduction

| | |
|---|---|
| **Situation** | Claude Code is most useful when it can run commands on its own: install, build, test, launch. I work on several projects: PWAs, Electron apps, a macOS app. |
| **Complication** | On the Mac itself, that gives an agent your whole machine. One devcontainer per project means seven setups, seven logins and a pile of workarounds. One devcontainer with the projects mounted is slow, and file watching and `node_modules` break across the mount. |
| **Question** | How do you give Claude a real dev machine that is separate from the Mac, without losing GUI apps or the macOS toolchain? |
| **Answer** | One Lima VM, defined in one file, connected over SSH. |

## Key line: three arguments (MECE: the box, the connection, the work)

1. **One VM is a simpler and safer box for the agent.**
   - `dev.yaml` is the only source of truth. If something is installed in the VM and not in `dev.yaml`, that is a bug.
   - No host mounts. The VM has its own GitHub key and no SSH agent forwarding.
   - One login for Claude and `gh`. One toolchain. It replaces the per-project devcontainers and all their workarounds.

2. **The Claude desktop app connects to it over SSH.**
   - Environment dropdown → Add SSH connection → `lima-dev`. Claude Code installs itself in the VM.
   - The same SSH host serves JetBrains Gateway and VS Code Remote-SSH.
   - Two gotchas: the SSH port changes on restart (re-run `bootstrap.sh`), and the SSH control master keeps old sessions (`ssh -O exit lima-dev`).

3. **Every kind of app has a path.**
   - **PWA:** the dev server runs in the VM. Lima forwards the ports, so the Mac browser opens `localhost:5173`. Playwright and Supabase run in the VM too.
   - **Electron:** the app launches in the VM. Tests run under `xvfb-run`. To watch the app, open `vnc://localhost:5901` in macOS Screen Sharing. An AppArmor setting keeps Electron's sandbox on.
   - **macOS app:** Xcode, the iOS Simulator and `electron-builder --mac` stay on the host. Claude commits in the VM, and the host fetches the commit through GitHub or straight from the VM as a git remote.

## The costs (said honestly)

- Nothing in the VM is backed up. Push before you stop for the day.
- No snapshots under `vmType: vz`. Recovery is a rebuild, so `dev.yaml` must be complete.
- `@mention` of files does not work in desktop-app SSH sessions. File attachment does.
- A toolchain bump hits every project at once.

## Call to action

Clone the repo, run `./bootstrap.sh`, run `setup-github.sh` in the VM, then add `lima-dev` as an SSH connection in the Claude desktop app.
