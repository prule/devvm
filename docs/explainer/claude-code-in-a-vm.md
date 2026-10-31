---
title: "Claude Code in a VM: One Linux Box for PWAs, Electron and macOS Apps"
date: 2026-10-24T10:00:00+11:00
publishDate: 2026-10-24
draft: true
layout: "post"
tags: ["claude-code", "lima", "vm", "electron", "pwa", "macos", "devenv"]
categories: ["coding"]
description: "Run Claude Code in one Lima VM, drive it from the Claude desktop app over SSH, and still build PWAs, Electron apps and a macOS app."
author: "Paul"
---

**Put Claude Code in one Linux VM on your Mac, and drive it from the Claude desktop app over SSH.** The agent gets a full machine it can rebuild from one file, separate from your Mac. PWAs and Electron apps run in the VM from start to finish. Only native macOS builds go back to the host, and only git crosses the boundary.

Three reasons this works:

1. **One VM is a simpler and safer box for the agent.** One file defines it, nothing from the Mac is mounted, and it has one login.
2. **The Claude desktop app connects to it over SSH.** No plugin, no sshd in a container, no workarounds.
3. **Every kind of app has a path.** PWAs and Electron apps run fully in the VM. macOS builds use a short git round trip.

The setup is in [prule/devvm](https://github.com/prule/devvm).

{{< mermaid >}}
flowchart LR
  subgraph Mac["macOS host (thin)"]
    CD["Claude desktop app"]
    BR["Browser<br/>localhost:5173"]
    SS["Screen Sharing<br/>vnc://localhost:5901"]
    XC["Xcode / iOS Simulator<br/>electron-builder --mac"]
  end
  subgraph VM["Lima VM 'dev' (Ubuntu 24.04)"]
    CC["Claude Code"]
    SRC["~/projects/current<br/>every repo"]
    DEV["Vite · Playwright · Supabase"]
    EL["Electron on Xvfb :99"]
  end
  CD -- SSH --> CC
  BR -- port forward --> DEV
  SS -- port forward --> EL
  XC -- git fetch --> SRC
{{< /mermaid >}}

## Why not just run it on the Mac?

Claude Code is most useful when it can run commands on its own: install, build, test, launch. On the Mac, that gives an agent your whole machine.

I tried the usual fixes first:

- **One devcontainer per project.** Seven projects meant seven setups, seven logins, and workarounds like `CLAUDE_CONFIG_DIR`, `GH_CONFIG_DIR` and a shared `/cache` volume.
- **One devcontainer with the projects mounted.** Every `pnpm install`, `git status` and build crosses virtiofs. File watching across the mount is unreliable. `node_modules` ends up with native binaries for whichever OS installed last.

The VM fixes both problems. The longer comparison is in [One VM Instead of Seven Dev Containers](https://prule.github.io/pauls-blog/post/coding/2026/one-vm-instead-of-seven-devcontainers/).

## 1. One VM is a simpler, safer box

**One file defines the machine.** `dev.yaml` holds the Lima config and all the provisioning: Node, pnpm, Java through SDKMAN, Docker, Supabase CLI, Playwright, Electron's libraries, the display. One rule keeps it honest:

{{< notice type="warning" >}}
If something is installed in the VM and not in `dev.yaml`, that is a bug in `dev.yaml`.
{{< /notice >}}

`vmType: vz` has no snapshots, so recovery is `limactl delete dev && ./bootstrap.sh`. That only works if the file is complete. Never fix a missing package with a bare `sudo apt install`.

**The Mac is out of reach.** `mounts: []`. The VM has its own GitHub key, and `bootstrap.sh` removes `ForwardAgent yes` if it ever appears. If Claude does something wrong in the VM, the worst case is a rebuild.

**One login, one toolchain.** `~/.claude` and `~/.config/gh` exist once. All the per-container workarounds are gone. Each one is marked `GONE:` in `dev.yaml`, so you can review what was left out.

## 2. The desktop app connects over SSH

```bash
./bootstrap.sh
limactl copy setup-github.sh dev:/tmp/ && limactl shell dev -- bash /tmp/setup-github.sh
```

`bootstrap.sh` creates the VM and writes a `lima-dev` block to `~/.ssh/config`. Then in the Claude desktop app: environment dropdown → **+ Add SSH connection** → host `lima-dev`. Leave the port and identity file empty. Claude Code installs itself in the VM the first time you connect.

JetBrains Gateway and VS Code Remote-SSH use the same host. The IDE backend runs next to the code, and only the thin client runs on the Mac.

Two things will catch you out:

- **The SSH port changes when the VM restarts.** `ssh lima-dev` fails with `Connection refused`. Re-run `./bootstrap.sh`. It is safe to run again.
- **Lima reuses SSH connections.** A session can be older than a change you just made, for example being added to the `docker` group. Run `ssh -O exit lima-dev` and reconnect.

## 3. Every kind of app has a path

### PWAs: everything runs in the VM

The dev server runs in the VM. Lima forwards guest ports bound to `0.0.0.0` on its own. `dev.yaml` also declares the ports bound to `127.0.0.1` that it knows about: 5173–5175 for Vite, 4173 for preview, 54321–54324 for Supabase.

```ts
// vite.config.ts
export default defineConfig({
  server: { host: true },
});
```

Open `http://localhost:5173` in the Mac browser. Browsers treat `localhost` as a secure context, so service workers and the install prompt behave as they would locally. Playwright, Supabase in Docker and the unit tests all run in the VM, where Claude can run them itself.

### Electron: launch in the VM, watch over VNC

Electron apps have to **launch** here, not only compile: the unit tests run inside Electron, and Playwright e2e runs against a packaged build. `dev.yaml` sets up three things:

- **GTK/X/NSS runtime libraries**, installed explicitly. Playwright's `--with-deps` does not cover them all.
- **`xvfb`** for a display. Tests run under `xvfb-run -a …`.
- **`kernel.apparmor_restrict_unprivileged_userns = 0`.** Ubuntu 23.10 and later block Electron's sandbox through AppArmor. This setting fixes it with the sandbox still on. `--no-sandbox` would turn off a real security boundary.

To **see** the app, `dev.yaml` runs a second display: Xvfb on `:99`, served by x11vnc on port 5901, localhost only.

```bash
DISPLAY=:99 pnpm dev
```

On the Mac: Finder → **Go → Connect to Server** (⌘K) → `vnc://localhost:5901`. Get the password with `ssh lima-dev cat .vnc/password.txt`.

{{< notice type="tip" >}}
`DISPLAY` is set per command on purpose. If it were set for the whole machine, ssh would try to start an X askpass helper in Claude's non-interactive shells, and git over ssh would break.
{{< /notice >}}

Test windows never appear on the screen you are watching. `xvfb-run -a` finds `:99` taken and uses `:100` or higher.

### macOS apps: build on the host, move code with git

Xcode, the iOS Simulator and `electron-builder --mac` need macOS. Claude writes the code in the VM. The host keeps its own checkout, with its own `node_modules`, and builds it.

1. **In the VM: commit.** Uncommitted changes do not travel. A `wip:` commit is fine.
2. **Move the commit to the host.**
3. **On the host: `pnpm install` if the lockfile changed, then build and run.**
4. **Fix things in the VM.** If you fix something on the host, send it back.

For step 2, either push through GitHub, or add the VM as a git remote and skip GitHub:

```bash
# host, once per repo
git remote add vm lima-dev:projects/current/my-repo

# each time
git fetch vm
git switch -c my-branch vm/my-branch    # first time
git pull vm my-branch                   # after that
```

To send a host fix back, push under a different branch name, because git refuses to push into the branch the VM has checked out:

```bash
git push vm HEAD:refs/heads/from-host   # host
git merge from-host && git branch -d from-host   # VM
```

## What it costs

- **No backup.** `~/.lima` is excluded from Time Machine. Code is safe only when it is pushed. Push before you stop for the day.
- **No snapshots.** Recovery is a rebuild, so `dev.yaml` has to be complete.
- **`@mention` of files does not work** in desktop-app SSH sessions. File attachment does. This is the one real day-to-day loss.
- **One toolchain for every project.** Bumping Node bumps it everywhere. Renovate opens the PRs, and major bumps wait for you to approve them.
- **Sizing.** 6 CPU and 14 GB RAM, because the VM runs an IDE backend, the agent and the builds together. The disk ceiling is 60 GiB, against a measured peak of about 20 GB.

## Start here

```bash
git clone git@github.com:prule/devvm.git && cd devvm
./bootstrap.sh
limactl copy setup-github.sh dev:/tmp/ && limactl shell dev -- bash /tmp/setup-github.sh
./clone-all.sh --dry-run
```

Then add `lima-dev` as an SSH connection in the Claude desktop app, and ask Claude to run your tests.
