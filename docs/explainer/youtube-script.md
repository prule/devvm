# YouTube script: Claude Code in a VM

**Working title:** I gave Claude Code its own Linux machine. Here's how I still ship PWAs, Electron and macOS apps.
**Length:** about 10 minutes. About 900 spoken words, so roughly 6 minutes of narration at a normal pace; the rest is screen demos with no VO.
**Voiceover:** [tts/](tts/README.md) generates it from this file, one clip per section.
**Structure:** Pyramid Principle. The answer comes in the first 30 seconds, then the three supporting arguments, then the evidence for each.
**Storyline:** [storyline.md](storyline.md). The slide deck uses the same order, so its slides can be the B-roll for the talking-head parts.

Each block has **VO** (what you say) and **SCREEN** (what the viewer sees). Times are targets.

---

## 0:00 — Cold open: the answer (30s)

**SCREEN:** Claude desktop app. The environment dropdown shows `lima-dev`. Claude runs `pnpm test` and it passes. Cut to an Electron window in macOS Screen Sharing.

**VO:**
> Claude Code is running in a Linux VM on my Mac. I drive it from the Claude desktop app over SSH. It builds and runs my PWAs and my Electron apps in that VM. The only thing that comes back to the Mac is the native macOS build, and the only thing that crosses over is git.
>
> In this video: why one VM, how the desktop app connects, and how each kind of app works.

**SCREEN:** Title card. Three numbered lines: *1. The box · 2. The connection · 3. The apps*.

---

## 0:30 — The problem (60s)

**SCREEN:** Slide: Situation → Complication → Question.

**VO:**
> Claude Code is most useful when it can run commands on its own. Install, build, test, launch. On my Mac, that means giving an agent my whole machine.
>
> So I tried devcontainers. One per project. That was seven setups, seven logins, and a pile of workarounds to share caches and config between them.
>
> Then one devcontainer with everything mounted. That's slow. Every `pnpm install` and every `git status` crosses the mount, file watching misses changes, and `node_modules` ends up with binaries for the wrong OS.
>
> So the question is: how do I give Claude a real dev machine that's separate from my Mac, without losing GUI apps or Xcode?

**SCREEN:** Answer slide: "One Lima VM. One file. Connected over SSH."

---

## 1:30 — Point 1: One VM is a simpler, safer box (2 min)

**SCREEN:** Architecture diagram: thin Mac on the left, VM on the right, SSH arrows.

**VO:**
> The first point. One VM is a simpler and safer box for the agent.

**SCREEN:** `dev.yaml` open in the editor. Scroll through the `param:` block and the provision steps.

**VO:**
> The whole machine is this one file, `dev.yaml`. Lima config, Node, pnpm, Java, Docker, Supabase, Playwright, Electron's libraries. And one rule: if something is installed in the VM and not in this file, that's a bug in this file.

**SCREEN:** Highlight the rule. Then `vmType: vz` and the comment about no snapshots.

**VO:**
> That rule matters because there are no snapshots. If the VM breaks, I delete it and run bootstrap again. That only works if the file is complete. So I never `apt install` by hand.

**SCREEN:** Highlight `mounts: []`. Then the `ForwardAgent` line in `bootstrap.sh`.

**VO:**
> Nothing from the Mac is mounted. The VM has its own GitHub key, and no SSH agent forwarding. If Claude does something wrong in there, the worst case is a rebuild.

**SCREEN:** `grep GONE: dev.yaml`.

**VO:**
> And one login. Claude and the GitHub CLI log in once. All the devcontainer workarounds are gone, and each one is marked `GONE:` in the file, so I can see what I left out.

---

## 3:30 — Point 2: The desktop app connects over SSH (1 min 30s)

**SCREEN:** Terminal on the Mac. Run `./bootstrap.sh`. Show the `lima-dev` block it writes in `~/.ssh/config`.

**VO:**
> The second point. The Claude desktop app connects to the VM over SSH, with nothing extra to install.
>
> `bootstrap.sh` creates the VM and writes an SSH config entry called `lima-dev`.

**SCREEN:** Claude desktop app → environment dropdown → **+ Add SSH connection** → type `lima-dev` → connect. Claude installs itself.

**VO:**
> In the desktop app, I add an SSH connection, type `lima-dev`, and leave the port and key empty. On the first connect, Claude Code installs itself in the VM. JetBrains Gateway and VS Code use the same host.

**SCREEN:** Lower-third callouts, one at a time: "Port changes on restart → re-run bootstrap.sh" and "Stale session → ssh -O exit lima-dev".

**VO:**
> Two things will catch you out. The SSH port changes every time the VM restarts, so re-run bootstrap. And Lima reuses SSH connections, so after a group or environment change, drop the old connection with `ssh -O exit`.

---

## 5:00 — Point 3: Every kind of app has a path (4 min)

**SCREEN:** Three-column slide: PWA · Electron · macOS.

**VO:**
> The third point. Every kind of app I build has a path. Two run fully in the VM. One goes back to the Mac.

### 5:10 — PWA (1 min)

**SCREEN:** Claude runs `pnpm dev` in the VM. Cut to the Mac browser at `localhost:5173`. Open DevTools → Application → Service Workers.

**VO:**
> PWAs first. The dev server runs in the VM. Lima forwards the ports, so the browser on my Mac opens `localhost:5173`. Browsers treat localhost as secure, so the service worker and the install prompt work the same as local.

**SCREEN:** `server: { host: true }` in `vite.config.ts`. Then the `portForwards` block in `dev.yaml`.

**VO:**
> Set `host: true` in the Vite config. `dev.yaml` also forwards the usual ports: Vite, preview, Supabase. Playwright and Supabase run in the VM, so Claude can run the whole test suite itself.

### 6:10 — Electron (1 min 30s)

**SCREEN:** Claude runs `xvfb-run -a pnpm test`. It passes.

**VO:**
> Electron. The app has to actually launch in the VM, because the tests run inside Electron. There's no screen, so tests run under `xvfb-run`.

**SCREEN:** The Chromium sandbox FATAL error. Then the `apparmor_restrict_unprivileged_userns` line in `dev.yaml`.

**VO:**
> On Ubuntu 23.10 and later, you hit this sandbox error. The fix is one kernel setting, and the sandbox stays on. Don't use `--no-sandbox`.

**SCREEN:** Claude runs `DISPLAY=:99 pnpm dev`. On the Mac: ⌘K → `vnc://localhost:5901` → enter the password → the app window appears.

**VO:**
> To see the app, the VM runs a second display, served over VNC on localhost. I start the app on display 99, open Screen Sharing on the Mac, and there it is. Test windows go to a different display, so they never cover the one I'm watching.

### 7:40 — macOS app (1 min 20s)

**SCREEN:** Four-step loop diagram: commit in VM → fetch on host → install and build → fix in VM.

**VO:**
> Finally, macOS. Xcode, the iOS Simulator and the Mac Electron build need macOS. So Claude writes the code in the VM, and the Mac builds it. Only git crosses over.

**SCREEN:** Host terminal: `git remote add vm lima-dev:projects/current/my-repo`, `git fetch vm`, `git switch -c my-branch vm/my-branch`. Then Xcode builds and runs.

**VO:**
> Claude commits in the VM. On the Mac, I add the VM as a git remote and fetch from it directly. No GitHub needed, and throwaway commits never show up in the repo. Then I build in Xcode as usual. If I fix something on the Mac, I push it back under a different branch name and merge it in the VM.

---

## 9:00 — What it costs (40s)

**SCREEN:** Four-row costs slide.

**VO:**
> What does it cost? Nothing in the VM is backed up, so push before you stop for the day. There are no snapshots, so the file has to be complete. `@mention` of files doesn't work in SSH sessions, but attaching files does. And a toolchain bump hits every project at once. For me, that's a fair trade.

---

## 9:40 — Recap and call to action (20s)

**SCREEN:** The pyramid slide: governing thought on top, three points below.

**VO:**
> So: one VM, one file, one SSH connection. PWAs and Electron run in the VM, and macOS builds come home over git. The repo is linked below. Run bootstrap, add the SSH connection, and let Claude run your tests.

**SCREEN:** End card with the repo URL `github.com/prule/devvm` and a link to the blog post.

---

## Description box

```text
Claude Code runs in one Linux VM on my Mac. I drive it from the Claude desktop app over SSH, and I still build PWAs, Electron apps and a macOS app.

0:00 The answer
0:30 The problem with devcontainers
1:30 One VM is a simpler, safer box
3:30 Connecting the Claude desktop app over SSH
5:00 PWAs
6:10 Electron
7:40 macOS apps
9:00 What it costs
9:40 Recap

Repo: https://github.com/prule/devvm
Background: https://prule.github.io/pauls-blog/post/coding/2026/one-vm-instead-of-seven-devcontainers/
```

## Shot list (record before editing)

- [ ] Claude desktop app: add the SSH connection, first connect, Claude installs itself
- [ ] Claude runs `pnpm test` in a PWA repo
- [ ] Mac browser on `localhost:5173`, DevTools showing the service worker
- [ ] `xvfb-run -a pnpm test` in an Electron repo
- [ ] Electron window in macOS Screen Sharing (`vnc://localhost:5901`)
- [ ] Host: `git fetch vm`, then an Xcode build and run
- [ ] `dev.yaml` scroll-through: the rule, `mounts: []`, `portForwards`, the AppArmor line
