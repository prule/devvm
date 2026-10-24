# devvm

One Linux VM for every project, driven by the Claude Code desktop app over SSH.

Replaces the per-project `.devcontainer/` setup. Rationale and trade-offs:
[One VM Instead of Seven Dev Containers](https://prule.github.io/pauls-blog/post/coding/2026/one-vm-instead-of-seven-devcontainers/).

```
macOS host (thin)                      Lima VM "dev" (Ubuntu 24.04 arm64)
├── Claude Code desktop app ───SSH───► ├── ~/projects/current/…  every repo
├── JetBrains Gateway ───────SSH───►   ├── WebStorm backend (Gateway installs)
│   (thin client only)                 ├── Node, pnpm, OpenSpec (pinned in dev.yaml)
├── Browser → localhost:5173           ├── SDKMAN: Java 25 + 21, Playwright, Electron
├── Xcode / iOS Simulator              ├── Docker, Supabase CLI
└── Time Machine (excludes ~/.lima)    └── ~/.claude, ~/.config/gh (one login)

Two thin clients on the Mac, one box doing the work. No shared folders.
```

## Files

| | |
|---|---|
| `dev.yaml` | The environment. Lima config + all provisioning. **The only source of truth.** |
| `bootstrap.sh` | Host-side. Creates the VM, writes the `lima-dev` SSH config block, excludes `~/.lima` from Time Machine. |
| `setup-github.sh` | Run once in the VM. VM-only SSH key + `gh auth login`. Interactive, so it can't live in `dev.yaml`. |
| `make-manifest.sh` | Regenerates `repos.tsv`, `worktrees.tsv` and `not-in-git.txt` from a populated checkout. Run on the host. |
| `clone-all.sh` | Run in the VM. Clones every project from the manifest, adds the worktrees, warns about what git does not cover. |
| `migrate-repo.sh` | Run in the VM, once per repo. Drops `.devcontainer/`, pins Node, installs deps. |
| `renovate.json` | Tells Renovate how to find the version pins in `dev.yaml`. See **Bumping the toolchain**. |

## Quickstart

```bash
./bootstrap.sh
limactl copy setup-github.sh dev:/tmp/ && limactl shell dev -- bash /tmp/setup-github.sh
```

Check out every project:

```bash
./clone-all.sh --dry-run    # see what it would do
./clone-all.sh              # clone everything missing
```

Then in the Claude Code desktop app: environment dropdown → **+ Add SSH connection** → host `lima-dev`, leave port and identity file empty (they come from `~/.ssh/config`). Claude Code installs itself on the VM on first connect.

Verify:

```bash
limactl shell dev -- bash -lc 'node -v; pnpm -v; openspec --version; java -version; docker run --rm hello-world'
```

`java -version` must report **25**. Two JDKs are installed, so this is worth
actually reading rather than glancing at.

## Getting a shell in the VM

Three ways in, all equivalent once `bootstrap.sh` has run:

```bash
ssh lima-dev          # via the ~/.ssh/config block bootstrap.sh writes
limactl shell dev     # Lima's own, no SSH config needed
```

**Claude Code desktop app:** environment dropdown → **+ Add SSH connection** → SSH Host `lima-dev`, leaving port and identity file empty so they come from `~/.ssh/config`. Claude Code installs itself on the VM on first connect.

**WebStorm** connects over the same SSH host via Gateway — see below.

### Two things that will catch you out

**The SSH port changes when the VM restarts.** Lima picks a new forwarded port each time, so the `~/.ssh/config` block goes stale and `ssh lima-dev` fails with `Connection refused`. Re-run `./bootstrap.sh` (idempotent — it rewrites the block), or just:

```bash
limactl show-ssh dev --format=config    # shows the current port
```

A saved connection in the desktop app or Gateway will need the same refresh. `limactl shell dev` is unaffected, which makes it the better choice when something looks broken.

**Lima multiplexes SSH through a control master,** so a connection can outlive a change you just made inside the VM. Group membership is the usual victim: after provisioning added the login user to `docker`, every `docker` command still failed with `permission denied` because the session predated it. Drop the shared connection and reconnect:

```bash
ssh -O exit lima-dev
```

The same applies to anything PAM reads at session start — `/etc/environment`, so `JAVA_HOME` and `PATH`. If an environment change seems not to have taken effect, you are probably still on the old connection rather than looking at a real bug.

## WebStorm

```bash
brew install --cask jetbrains-gateway
```

Gateway → **SSH** → `lima-dev` → pick a project under `~/projects/current`. It downloads the WebStorm backend into the VM on first connect; the thin client is the only JetBrains process on the Mac.

This is the same architecture the dev containers used via `"jetbrains": { "backend": "WebStorm" }` — IDE backend next to the code, GUI on the host.

It is also why there is no shared folder. A writable mount of `~/projects/current` would put `node_modules` on both sides of the boundary, where native binaries (esbuild, rollup, sharp) belong to whichever OS installed last — exactly what the containers' per-project `node_modules` volumes prevented. Keeping `node_modules` VM-local instead left the host IDE unable to resolve an import. Moving the IDE to the code's side of the boundary dissolves the problem rather than trading around it, and JetBrains wants local disk for the backend anyway — network filesystems are explicitly unsupported.

`dev.yaml` provisions the two things the backend needs from the OS: a few X/font libraries, and `fs.inotify.max_user_watches = 524288` (below roughly that, the IntelliJ platform stops watching files and falls back to recursive rescans).

## VS Code (browsing and copying files)

There is no shared folder, so moving files between the Mac and the VM needs a client on the Mac. VS Code's Remote-SSH gives you a file tree you can drag and drop into.

```bash
brew install --cask visual-studio-code
```

Install the **Remote - SSH** extension (Microsoft), then ⇧⌘P → **Remote-SSH: Connect to Host…** → `lima-dev` → **Linux**. It installs its server in the VM on first connect. **File → Open Folder…** → `~/projects/current/`.

- **Mac → VM:** drag files from Finder into the Explorer sidebar.
- **VM → Mac:** right-click → **Download…**

**Docker containers:** while connected, install the **Container Tools** extension (it installs on the VM side). Expand a running container → **Files** to browse it and download files from it. If it reports `permission denied` on Docker, the VS Code server predates the `docker` group change. Run **Remote-SSH: Kill VS Code Server on Host…** and reconnect.

The SSH port gotcha above applies here too: after a VM restart, re-run `./bootstrap.sh` before reconnecting.

## Checking out the projects

`clone-all.sh` reads `repos.tsv` — a manifest of `path  owner/repo  branch`. Generate it on the host from your existing checkout:

```bash
./make-manifest.sh              # scans ~/projects/current
./make-manifest.sh ~/code       # or another root
```

The manifest is hand-editable and is the source of truth for what gets cloned. What it records:

- **Paths, aligned to repo names.** By default a directory whose name differs from its repo (`toolbox` holding `tool-box`, say) is written under the repo name, so the VM's directory names can differ from the host's. Use `make-manifest.sh --as-is` to keep the host's names instead.
- **Branches.** Each repo is cloned on the branch it was on, not necessarily `main`.
- **Nested clones.** A plain folder holding several repos is fine: only the leaf directories are repos, and only they are listed. Submodules are left out, because `clone-all.sh` clones with `--recurse-submodules` and brings them along with their parent.
- **Worktrees.** These go in `worktrees.tsv` and are added with `git worktree add` once the parent exists. Their names are worktree labels, not repos, so they are not aligned.

**Repos checked out twice** (the same repo in two directories, or both standalone and as another repo's submodule) are cloned twice. That is usually leftover duplication on the host. Decide about it rather than inheriting it.

### What this does NOT cover

`not-in-git.txt` lists directories under the root that are **in no git repo at all**. A clone-based migration loses them silently, so `clone-all.sh` prints them last, every run. Copy what you want deliberately:

```bash
limactl copy -r ~/projects/current/<name> dev:/home/$USER/projects/current/
```

## JVM versions

SDKMAN owns every JDK; apt owns none. Same division as Node, where fnm owns the versions — one authority per language, so "which java is this?" has one answer.

```bash
sdk list java              # what is available
sdk install java 17.0.x-tem
sdk default java 25.0.4-tem   # moves the machine default, scripts included
sdk current java
```

`sdk default` repoints `~/.sdkman/candidates/java/current`, which is what `JAVA_HOME` in `/etc/environment` targets — so it changes the default for non-interactive shells too, from one place.

**Per project**, commit a `.sdkmanrc`:

```
java=21.0.12-tem
```

`sdkman_auto_env=true` is set, so `cd` into that directory switches the JDK. This is **interactive only** — it hooks `PROMPT_COMMAND`, so scripts and agent-run commands never see it.

For non-interactive correctness, **Gradle toolchains are the mechanism**, not `.sdkmanrc`:

```kotlin
kotlin { jvmToolchain(21) }
```

Gradle discovers every SDKMAN-installed JDK from the candidates directory, so a declared toolchain resolves without auto-provisioning a download mid-build.

## Electron

Electron apps have to *launch* here, not merely compile: unit tests run inside Electron, and Playwright e2e runs against a packaged build.

Three things make that work, all provisioned:

- **The GTK/X/NSS runtime libraries.** Playwright's `--with-deps` covers some of them but not all, and it is a best-effort step, so Electron's set is installed explicitly.
- **`xvfb`.** There is no physical display in this VM. Run tests and anything else that opens a window you don't need to see under `xvfb-run -a …`. To *watch* an app, see **Seeing the window** below.
- **`kernel.apparmor_restrict_unprivileged_userns = 0`.** Ubuntu 23.10+ restricts unprivileged user namespaces through AppArmor, which breaks Electron's sandbox:

  ```
  FATAL:setuid_sandbox_host.cc] The SUID sandbox helper binary was found, but
  is not configured correctly. Rather than run without sandboxing I'm aborting
  now. You need to make sure that .../chrome-sandbox is owned by root and has
  mode 4755.
  ```

  Allowing unprivileged userns fixes this **with the sandbox left on**. The two common alternatives are worse: `--no-sandbox` turns off a real security boundary, and `chown root:root` + `chmod 4755` on `chrome-sandbox` has to be redone after every `node_modules` install.

Verified in this VM: `xvfb-run -a electron main.js` → `ELECTRON OK 44.7.0 chrome 152.0.7977.130`, sandbox enabled.

### Seeing the window

`xvfb-run` makes a throwaway display that nobody can see. For looking at an app, `dev.yaml` also runs a persistent one: Xvfb on display `:99` (1920×1080), served over VNC by x11vnc. Two systemd units, `devvm-display` and `devvm-vnc`, start on boot.

Start the app on that display. `DISPLAY` is set per command on purpose (see below):

```bash
DISPLAY=:99 pnpm dev        # or: DISPLAY=:99 npx electron .
```

Then on the Mac, Finder → **Go → Connect to Server…** (⌘K) → `vnc://localhost:5901`. That opens macOS's built-in Screen Sharing. It asks for a password, which provisioning generated:

```bash
ssh lima-dev cat .vnc/password.txt
```

How it is set up:

- **Port 5901, not 5900.** The Mac's own Screen Sharing server owns 5900 when it is turned on.
- **x11vnc listens on the VM's localhost only** (`-localhost`). The `portForwards` entry is what makes it reachable from the Mac, and only from the Mac's localhost. The password exists because Screen Sharing insists on one; localhost is the real boundary.
- **Tests don't land on it.** `xvfb-run -a` starts looking at `:99`, finds it taken and moves to `:100` and up, so test windows never appear on the screen you are watching.
- **`DISPLAY` is not set machine-wide.** When `DISPLAY` is set and there is no tty, ssh tries to start an X askpass helper, which would break git over ssh in the agent's non-interactive shells. Opt in per command instead.
- **There is no window manager.** Windows have no title bars and can't be moved or resized by dragging. That's fine for looking at one app. If it gets in the way, add one (for example `openbox`) to `dev.yaml` rather than installing it by hand.

If Screen Sharing can't connect, check the services, and on the Mac check that the port is forwarded:

```bash
ssh lima-dev systemctl status devvm-display devvm-vnc
lsof -iTCP:5901 -sTCP:LISTEN
```

Verified in this VM: `DISPLAY=:99 electron main.js` opens a visible 800×600 window, and x11vnc on `127.0.0.1:5901` answers `RFB 003.008` with password auth. Not yet verified: the Mac end, meaning Screen Sharing through Lima's forward. An existing VM picks all of this up, port forward included, through **Applying a `dev.yaml` change without a rebuild** below. The block is safe to run on every boot: it keeps an existing password and rewrites the units unchanged.

### What cannot move here

`electron-builder --mac` needs macOS — codesigning and `.dmg` creation are not available on Linux. **That build stays on the host**, alongside Xcode. A bare `electron-builder --dir` still works in the VM, but produces a *Linux* build rather than the macOS one the host produced; fine for tests, worth knowing when comparing artefacts. Per-OS release builds remain CI's job.

How to get a change from the VM onto the host to build and run it: **Running macOS-only builds on the host** below.

## Running macOS-only builds on the host

Some things only work on macOS: `electron-builder --mac`, Xcode, and the iOS Simulator. For those, the code is written in the VM and built on the host. The host keeps its own checkout of each such repo, with its own `node_modules` holding macOS-native binaries. **Only git crosses the boundary.** There is no shared folder (see **WebStorm** for why).

The loop:

1. **In the VM: commit.** Uncommitted changes do not travel. A `wip:` commit is fine; squash it later.
2. **Move the commit to the host.** There are two ways to do it; see below.
3. **On the host: install, build and run.** Run `pnpm install` whenever the lockfile changed: the host's `node_modules` is separate and won't follow along. Then build and run as usual.
4. **Fix things in the VM, not on the host.** Small fixes on the host are fine, but commit them and send them back (see below). Otherwise the two checkouts drift apart.

### Option A: through GitHub

Use this when the branch is going to be pushed anyway, for example for a PR or CI.

```bash
# VM
git push -u origin my-branch
```

```bash
# host
git fetch origin && git switch my-branch    # first time
git pull                                     # after that
```

### Option B: straight from the VM

The host can already `ssh lima-dev`, so it can fetch from the VM's checkout directly as a git remote. This skips GitHub entirely. Unpushed and throwaway commits work, and nothing appears in the repo's branch list. Add the remote once per repo, on the host:

```bash
git remote add vm lima-dev:projects/current/my-repo
```

The path is relative to the VM home directory and uses the **VM** directory name, which may differ from the host's (see **Checking out the projects**). Then each time:

```bash
git fetch vm
git switch -c my-branch vm/my-branch    # first time
git pull vm my-branch                   # after that
```

Things to know about Option B:

- **After a VM restart, re-run `./bootstrap.sh` first.** Otherwise `git fetch vm` fails with `Connection refused` because the SSH port changed (see **Two things that will catch you out**).
- **Sending host commits back:** git refuses to push into the branch the VM has checked out. Push under a different name and merge it in the VM:

  ```bash
  # host
  git push vm HEAD:refs/heads/from-host
  ```

  ```bash
  # VM
  git merge from-host && git branch -d from-host
  ```

- **It is not a backup.** `~/.lima` is excluded from Time Machine, so commits that exist only in the VM and on the host's `vm/*` refs are still unpushed work. Push anything you want to keep.

## The rule

> **If something is installed in the VM and not in `dev.yaml`, that is a bug in `dev.yaml`.**

`vmType: vz` means no snapshots (`limactl snapshot` is QEMU-only). There is no restore point — recovery is `limactl delete dev && ./bootstrap.sh`, which only works if this file is complete. So never fix a missing package with a bare `sudo apt install`; add it here and reprovision.

Nothing in the VM is backed up. Everything that matters is in git — so push before you stop for the day. That is an obligation, not a shrug.

## Bumping the toolchain

Edit `param:` in `dev.yaml`, then:

```bash
limactl stop dev && limactl delete dev && ./bootstrap.sh
```

This bumps every project at once. That is the intent, and also the risk — it's the cost of dropping per-repo Dockerfiles. Do it deliberately, not incidentally.

### Applying a `dev.yaml` change without a rebuild

Lima runs the provision scripts on **every boot**, not only on create, so a restart is enough for an additive change such as a new entry in the skills list. It is the cheap path: the existing disk, clones and logins survive.

The catch: a restart reads the instance's own copy, `~/.lima/dev/lima.yaml`, which was taken from `dev.yaml` when the VM was created. Editing `dev.yaml` here changes nothing until that copy is replaced. On the host:

```bash
git pull
limactl stop dev
cp dev.yaml ~/.lima/dev/lima.yaml
limactl start dev
./bootstrap.sh    # the SSH port changed with the restart
```

Each provision step skips work it already did (the skills step skips any skill whose `SKILL.md` exists), so a restart re-runs them quickly. Check the result:

```bash
limactl shell dev -- ls ~/.claude/skills
```

A skill that fails to install does not fail the boot, so the `ls` is the check — a missing directory means a skipped skill. Install it by hand with the command in the skills step of `dev.yaml`. Start a new Claude Code session afterwards, because skills load at session start.

Use the full rebuild above instead when a change is not additive: removing a package, changing a version pin, or changing the disk.

### Renovate

[Renovate](https://docs.renovatebot.com/) opens a PR when a new version is released for Node, pnpm, OpenSpec, the Supabase CLI or the `skills` CLI. It needs the Renovate GitHub App installed on this repo.

Each pin in `param:` has a comment directly above it that tells Renovate where to look:

```yaml
  # renovate: datasource=npm depName=pnpm
  PNPM_VERSION: "12.4.2"
```

A regex custom manager in `renovate.json` matches every such pair. To track a new tool, add a `param:` value with a `# renovate:` line above it. Use any [datasource](https://docs.renovatebot.com/modules/datasource/), and add `extractVersion=` if the release tags have a prefix (see `SUPABASE_CLI_VERSION`). The comment must be on the line immediately above the value. If it isn't, Renovate silently skips that pin; nothing errors.

- **Minor and patch updates** open PRs on their own.
- **Major updates** wait on the Dependency Dashboard issue, and Renovate opens the PR only after you tick the box. A major Node or pnpm bump hits every project, so it should be a decision.
- **Java is not covered.** `JAVA_VERSIONS` holds SDKMAN identifiers (`25.0.4-tem`), and Renovate has no SDKMAN datasource. Bump these by hand.
- **Merging does not touch the running VM.** The new version arrives the next time you rebuild with the commands above.

## Gotchas

- **Sizing.** 6 CPU / 14 GB, up from 4/12, because the VM now runs a full IDE backend alongside the agent and the builds. JetBrains asks 2+ cores and 4 GB+ for the backend alone. This is the first knob to turn if it feels tight.
- **Disk: 60 GiB against a measured ~20 GB peak.** Source and git history are small; the weight is the pnpm store (~4.5 GB), Supabase's Docker images (~4 GB) and the IDE's indexes (~4 GB). `node_modules` is nearly free because pnpm hardlinks into the store on ext4 — except for repos on npm/yarn, which write flat duplicated trees with no dedup. Sparse, so the ceiling is not a reservation, but the image only ever grows: keep the ceiling below the host's free space, or a runaway build can fill the macOS boot volume. Growing a Lima disk later works; shrinking does not.
- **No host mounts.** `mounts: []`. Moving files: `limactl copy`, or git. See **WebStorm** above for why.
- **Java is the exception to "one version".** `JAVA_VERSIONS: "25.0.4-tem 21.0.12-tem"` — 25 is the default; 21 is there because some projects pin `jvmToolchain(21)`, and a missing toolchain JDK makes Gradle auto-provision mid-build or fail.
- **`java` must agree across shell modes.** `/etc/environment` puts `JAVA_HOME` and a `java` entry at the **tail** of `PATH`. The tail position is load-bearing: `sdkman-init` prepends its own entry in interactive shells and `sdk use`/`sdk env` rewrites *that* one, so a `java` ahead of it wins and silently breaks per-project switching — `sdk env` reports 21 while `java -version` still says 25.
- **`param:`, not `env:`.** Provision scripts only see `param:` values, as `$PARAM_<Key>`. `env:` sets the login environment and is invisible to provisioning — an easy and silent-looking mistake that actually aborts the provision under `set -u`.
- **Ports.** Lima auto-forwards guest ports bound to `0.0.0.0`. Ports bound to `127.0.0.1` *inside* the guest need a `portForwards` entry. `dev.yaml` declares the known ones (5173/4173/5174, 54321–54324); the robust fix is still `server: { host: true }` in `vite.config.ts`.
- **Docker group.** The first login after provisioning may not have the `docker` group yet. `limactl stop dev && limactl start dev` fixes it.
- **No agent forwarding, on purpose.** `bootstrap.sh` strips `ForwardAgent yes` if a regenerated SSH block ever introduces one. The VM has its own GitHub key.
- **`@mention` files** doesn't work in desktop-app SSH sessions. File attachment does. This is the one real day-to-day loss.
- **Xcode / iOS stays on the host.** Nothing simulator-related can move into the VM. See **Running macOS-only builds on the host** for the round trip.

## Why not one devcontainer with everything mounted?

The obvious alternative is one devcontainer for every project, with `~/projects/current` bind-mounted from the Mac. Isolation is the same: one container for everything is no more separated than one VM. The difference is where the files live. On macOS a container already runs inside Docker Desktop's Linux VM, so the two shapes are:

```
devcontainer + mount:  macOS (APFS) ──virtiofs──► Docker Desktop VM ──► container ──► tools
this repo:                                        Lima VM (ext4) ────────────────────► tools
```

What the mount costs:

- **Speed.** `pnpm install`, `node_modules`, `git status` and builds are all small-file workloads, and every one crosses virtiofs.
- **File watching.** inotify events across the mount are unreliable, so Vite, Jest and the IntelliJ indexer miss changes or fall back to polling.
- **`node_modules` on both sides.** See **WebStorm** above. The per-project volume fix leaves the host IDE unable to resolve imports.
- **pnpm can't hardlink** across filesystems, so it copies from the store instead. The disk budget in `dev.yaml` assumes hardlinks.
- **Case-insensitive APFS** under tools that assume Linux semantics.
- **Docker inside Docker.** Supabase needs a daemon. Docker-in-Docker is heavy. With a mounted host socket, bind-mount paths inside the container don't match what the daemon sees. In the VM, Docker is just Docker.
- **Kernel settings aren't yours.** `fs.inotify.max_user_watches` and systemd belong to Docker Desktop's VM, not the container.
- **Connecting is harder.** The Claude Code desktop app and Gateway speak SSH to a VM natively. A container needs an sshd or a devcontainer-aware client.

What the mount gives you that this setup does not:

- **Files on the Mac.** Time Machine, Finder and Xcode see them directly. Here `~/.lima` is excluded from Time Machine, so code is only safe once pushed, which is why `not-in-git.txt` exists.
- **Disposability.** Rebuilding a container is routine. This VM has no snapshots, and recovery is a reprovision that is only as good as `dev.yaml`.
- **Portability.** A `devcontainer.json` also runs in Codespaces or CI. `dev.yaml` is Lima-only.
- **No file-copying step.** Here that needs `limactl copy` or VS Code (see above).

Putting the projects in a named Docker volume instead of a mount removes the mount costs, but it also hides the files from the Mac. That leaves you with this VM plus a container layer and Docker Desktop, and Docker-in-Docker is still awkward.

For this workload (Node and pnpm, Supabase in Docker, IDE backends that want local disk), the mount hurts most, so the files live in the VM.

## What this replaces

Per-project `.devcontainer/` directories and their docs, Docker Desktop, and every workaround that existed only because the environments were separate: `CLAUDE_CONFIG_DIR`, `GH_CONFIG_DIR`, `PLAYWRIGHT_SKIP_BROWSER_GC`, `--add-host=host.docker.internal`, the shared `/cache` volume convention, the `pnpm config set store-dir` double-write under two `XDG_CONFIG_HOME` values, and the "never mount a volume at `PNPM_HOME`" rule.

Each of those is marked `GONE:` at the point in `dev.yaml` where the ported step used to be, so the omissions are reviewable rather than forgotten.
