# devvm

One Linux VM for every project, driven by the Claude Code desktop app over SSH.

Replaces the per-project `.devcontainer/` setup. Rationale and trade-offs:
[One VM Instead of Seven Dev Containers](https://prule.github.io/pauls-blog/post/coding/2026/one-vm-instead-of-seven-devcontainers/).

```
macOS host (thin)                      Lima VM "dev" (Ubuntu 24.04 arm64)
├── Claude Code desktop app ───SSH───► ├── ~/projects/current/…  every repo
├── JetBrains Gateway ───────SSH───►   ├── WebStorm backend (Gateway installs)
│   (thin client only)                 ├── Node, pnpm, OpenSpec (pinned in dev.yaml)
│                                      ├── SonarQube (Docker) + sonar-check
│                                      ├── Postgres (Docker): dev_ro + dev_rw
├── Browser → localhost:5173,          ├── SDKMAN: Java 25 + 21, Playwright, Electron
│   hugo.devvm:8000, sonar… (Caddy)    ├── Hugo dev server for pauls-blog
├── Xcode / iOS Simulator              ├── Docker, Supabase CLI, claude CLI, betterleaks
│                                      ├── graphify, Claude Code skills (caveman, …)
└── Time Machine (excludes ~/.lima)    └── ~/.claude, ~/.config/gh (one login)

Two thin clients on the Mac, one box doing the work. No shared folders.
```

## Files

| | |
|---|---|
| `dev.yaml` | The environment: Lima config, version pins, probes, and the list of provision steps in the order they run. **With `provision/` and `files/`, the only source of truth.** |
| `provision/` | One script per provision step, `<name>.sh`, its notes at the top. `dev.yaml` points at each with `file:`. |
| `files/` | What the data steps write into the VM: `sonar-check` and the other commands in `files/bin/`, the two `CLAUDE.md` files, the git hooks, the `apply-project-standards` skill. |
| `bootstrap.sh` | Host-side. Creates the VM, writes the `lima-dev` SSH config block, adds the `*.devvm` names to `/etc/hosts`, excludes `~/.lima` from Time Machine. |
| `update-vm.sh` | Host-side. Applies the current `dev.yaml` to the existing VM with a restart, no rebuild, and shows the boot's provision warnings. |
| `setup-github.sh` | Run once in the VM. VM-only SSH key + `gh auth login`. Interactive, so it can't live in `dev.yaml`. |
| `make-manifest.sh` | Regenerates `repos.tsv`, `worktrees.tsv` and `not-in-git.txt` from a populated checkout. Run on the host. |
| `clone-all.sh` | Run in the VM. Clones every project from the manifest, adds the worktrees, warns about what git does not cover. |
| `migrate-repo.sh` | Run in the VM, once per repo. Drops `.devcontainer/`, pins Node, installs deps. |
| `renovate.json` | Tells Renovate how to find the version pins in `dev.yaml`. See **Bumping the toolchain**. |

## Quickstart

**Prerequisite:** [Homebrew](https://brew.sh) on the Mac. `bootstrap.sh` uses it to install Lima, but it does not install Homebrew itself. Check with `brew --version`. If it is missing, install it from https://brew.sh first. Nothing else is needed on the host: Docker runs inside the VM, so you do not need Docker Desktop or Colima.

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
limactl shell dev -- bash -lc 'node -v; pnpm -v; openspec --version; claude --version; java -version; docker run --rm hello-world'
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

**The SSH port is pinned to 60022** (`ssh.localPort` in `dev.yaml`). By default Lima picks a new random port every time the VM starts, which left the `~/.ssh/config` block and Gateway's saved connection pointing at a dead port after each restart. Gateway in particular stores a port of its own that overrides `~/.ssh/config`, so in its SSH connection set **Port** to `60022`. If `ssh lima-dev` ever fails with `Connection refused`, check that the VM is running (`limactl list`) and that the block is current (`./bootstrap.sh` rewrites it). `limactl shell dev` doesn't depend on any of this, which makes it the better choice when something looks broken.

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

**Turn off SSH agent forwarding** in the WebStorm window, once: **Settings → Tools → SSH Agent Forwarding**, clear **Enable SSH agent Forwarding**. When it is on, the client passes the Mac's SSH agent into the VM. Then whenever git in the VM needs a key (a background fetch, say), it asks for the passphrase of the Mac's `~/.ssh/id_rsa` ("Failed to load specified key … ssh-add"). The VM does not need it: it has its own GitHub key from `setup-github.sh`, and keeping the Mac's keys out of the VM is the same reason `bootstrap.sh` strips `ForwardAgent`.

### Several repos in one window

WebStorm has no tabs for separate projects. Instead, one project holds several directories, and WebStorm finds each one's `.git`. The Git tool window, the branch widget and the commit dialog then handle each repo separately (one commit per repo). There are two ways to set it up:

- **Add repos to a project (recommended):** open one repo, then **Settings → Directories → Add Content Root** and pick the others. Each appears as a top-level folder in the Project view.
- **Open a parent folder:** choose a folder holding the repos as the project directory in Gateway.

Avoid opening all of `~/projects/current`. WebStorm would index every repo, `node_modules` and build folder included, competing for the VM's memory with SonarQube, Postgres and Claude sessions. If you do, right-click the repos you aren't using → **Mark Directory as → Excluded**.

Each run configuration has its own working directory, so point it at the right repo. Node is one interpreter for the whole project, unlike fnm's per-repo switching in a terminal, so set it per run configuration when repos pin different versions. Each repo's `tsconfig.json` and ESLint config are still picked up separately.

This is the same architecture the dev containers used via `"jetbrains": { "backend": "WebStorm" }` — IDE backend next to the code, GUI on the host.

It is also why there is no shared folder. A writable mount of `~/projects/current` would put `node_modules` on both sides of the boundary, where native binaries (esbuild, rollup, sharp) belong to whichever OS installed last — exactly what the containers' per-project `node_modules` volumes prevented. Keeping `node_modules` VM-local instead left the host IDE unable to resolve an import. Moving the IDE to the code's side of the boundary dissolves the problem rather than trading around it, and JetBrains wants local disk for the backend anyway — network filesystems are explicitly unsupported.

`dev.yaml` provisions the two things the backend needs from the OS: a few X/font libraries, and `fs.inotify.max_user_watches = 524288` (below roughly that, the IntelliJ platform stops watching files and falls back to recursive rescans).

### Java: use IntelliJ IDEA, not WebStorm

WebStorm has no Java support: no completion, refactoring, Gradle import or Java debugger, and the Java plugin can't be installed into it. For Java, choose **IntelliJ IDEA** in Gateway's IDE dropdown in place of WebStorm.

- **Remote development needs a paid subscription.** IntelliJ IDEA has been one download with a free tier since 2025.3. The free tier covers Java, Kotlin, Gradle and Maven, plus basic JavaScript/TypeScript since 2026.1. Gateway's remote mode is not in it, though, so the free tier can only open code on the Mac, and here the code lives only in the VM. Without a subscription, use VS Code for Java (see **VS Code → Java** below).
- **Ultimate covers what WebStorm does,** so one IntelliJ backend can serve Java and TypeScript repos, instead of two.
- **Each backend is its own JVM in the VM** (roughly 2–4 GB). WebStorm and IntelliJ backends running at once take a real share of the VM's 14 GiB, next to SonarQube and Postgres.
- **JDK:** set the project SDK to SDKMAN's install, `~/.sdkman/candidates/java/25.0.4-tem` or `21.0.12-tem` (see **JVM versions**).
- **Turn off SSH agent forwarding** in the IntelliJ window too, as for WebStorm above. It is a separate setting per IDE.

## VS Code (files, Docker, Java)

There is no shared folder, so moving files between the Mac and the VM needs a client on the Mac. VS Code's Remote-SSH gives you a file tree you can drag and drop into.

```bash
brew install --cask visual-studio-code
```

Install the **Remote - SSH** extension (Microsoft), then ⇧⌘P → **Remote-SSH: Connect to Host…** → `lima-dev` → **Linux**. It installs its server in the VM on first connect. **File → Open Folder…** → `~/projects/current/`.

- **Mac → VM:** drag files from Finder into the Explorer sidebar.
- **VM → Mac:** right-click → **Download…**

**Docker containers:** while connected, install the **Container Tools** extension (it installs on the VM side). Expand a running container → **Files** to browse it and download files from it. If it reports `permission denied` on Docker, the VS Code server predates the `docker` group change. Run **Remote-SSH: Kill VS Code Server on Host…** and reconnect.

If it fails with `Connection refused`, see the SSH port note under **Two things that will catch you out**.

**Port forwarding is off in VS Code.** Lima already forwards the VM's ports to the Mac, and VS Code's own automatic forwards took Mac ports Lima needed: VS Code held port 8000, so every `http://<name>.devvm:8000` hung. `dev.yaml` sets `remote.autoForwardPorts` to `false` in the VM's remote settings on every boot. If VS Code still forwards ports (its **Ports** panel lists them), set the same in the Mac's own VS Code settings.

### Java

VS Code is the free way to work on Java in the VM (IntelliJ IDEA needs a paid subscription for this; see **WebStorm → Java**). It uses Microsoft's **Extension Pack for Java**, which runs on the VM side and brings Red Hat's Java language server, the debugger, the test runner, and Maven and Gradle support. Connect to `lima-dev`, then **File → Open Folder…** → the repo.

`dev.yaml` sets this up on every boot:

- **The extension pack** is installed through the VS Code server in the VM. That server only exists after VS Code has connected once, so on a fresh VM, either install the pack from the Extensions view while connected, or run `./update-vm.sh` after the first connect. After that, VS Code keeps it updated.
- **The JDKs:** `java.configuration.runtimes` in the remote settings (⇧⌘P → **Preferences: Open Remote Settings (SSH: lima-dev)**) lists one entry per `JAVA_VERSIONS`, with `JAVA_DEFAULT` as the default. That key is rewritten on each boot, so change the JDKs in `dev.yaml`, not there. The rest of the file is yours. A settings file with comments can't be merged; the boot then warns and leaves it alone.

Gradle builds still resolve their JDK from `jvmToolchain(...)` (see **JVM versions**), so the runtimes setting mainly affects the editor and plain Maven projects.

Things to know:

- **Kotlin is limited in VS Code.** The Java pack doesn't cover it. For Kotlin-heavy repos, IntelliJ is much better.
- **The language server is a JVM too,** about 1–2 GB per open window. If the VM is short on memory, ⇧⌘P → **Java: Clean Java Language Server Workspace** resets a server that has grown or got confused.
- **Refactoring and Gradle work** are weaker than in IntelliJ, but completion, navigation, debugging and running tests all work.

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

- **`git fetch vm` fails with `Connection refused`** when the VM is stopped or the `~/.ssh/config` block is stale (see **Two things that will catch you out**).
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

## Blog preview (Hugo)

`dev.yaml` keeps Hugo's dev server for `pauls-blog` running whenever the VM is up. On the Mac, open:

http://hugo.devvm:8000/

That redirects to `/pauls-blog/`. The page includes drafts, and rebuilds and reloads the browser tab every time you save a file. The `/pauls-blog/` path comes from the blog's `baseURL`, so links work the same as on GitHub Pages.

How it is set up:

- **`blog-serve`** (in `/usr/local/bin`) runs `hugo server --buildDrafts --buildFuture --disableFastRender` in `~/projects/current/pauls-blog`, bound to the VM's localhost on port 1313. Caddy serves it at `hugo.devvm` (see **Names for services**). The server is started with `--baseURL http://hugo.devvm:8000/pauls-blog/` and `--liveReloadPort 8000`, so links and live reload go through Caddy too. `http://localhost:1313/pauls-blog/` still loads, but its links lead to `hugo.devvm` and live reload doesn't work there. If the theme submodule is empty, the script initialises it first. Drafts and future-dated posts are shown. Extra arguments go to `hugo server`.
- **The Hugo version comes from the blog**, not from `dev.yaml`: each boot installs the `HUGO_VERSION` in pauls-blog's `.github/workflows/hugo.yml`, so the preview builds with what the site deploys with. Renovate bumps it in pauls-blog. After merging a bump, run `git pull` in the VM's pauls-blog checkout, then `./update-vm.sh` on the Mac. Until then `blog-serve` logs a `WARNING` saying the versions differ. `dev.yaml`'s `HUGO_VERSION` is only used before the blog is cloned.
- **`devvm-blog.service`** runs `blog-serve` on boot. It uses `Restart=always`, so if the blog is not cloned yet, the service retries every 30 seconds and starts when the checkout appears.

To see Hugo's output (build errors, for example):

```bash
ssh lima-dev journalctl -u devvm-blog -f
```

To run it in a terminal instead, stop the service first, because only one server can use port 1313:

```bash
ssh lima-dev sudo systemctl stop devvm-blog
ssh lima-dev blog-serve
```

`sudo systemctl start devvm-blog` (or a VM restart) puts it back.

## Names for services

Each web service in the VM gets a name on the Mac, all on one port, 8000, so you don't need each service's own port:

| Name | Goes to (VM port) |
|---|---|
| http://hugo.devvm:8000 | 1313, the blog preview |
| http://sonar.devvm:8000 | 9000, SonarQube |
| http://home-fleet.devvm:8000 | 5173 (kept: its Supabase `site_url` and e2e setup expect 5173) |
| http://intentionhorizon.devvm:8000 | 5181 |
| http://rss-reader.devvm:8000 | 5182 |
| http://strength2.devvm:8000 | 5183 |
| http://strength.devvm:8000 | 5184 (`app/`) |
| http://leave-planner.devvm:8000 | 5185 |
| http://video-aggregator.devvm:8000 | 5200 |
| http://portfolio.devvm:8000 | 8789 (`wrangler pages dev --port 8789`) |

Each port is set in the project's own repo, so the dev server always starts there. A name shows `502 Bad Gateway` until you start that project's dev server (`pnpm dev`). New ports go up from 5186.

How it works:

- **Caddy runs in the VM** on port 80, bound to the VM's localhost. It reads the `Host` header and passes each request to that name's port. The Caddyfile is in `provision/caddy.sh`, and every boot rewrites `/etc/caddy/Caddyfile` from it, so make changes there, not in the VM.
- **One `portForwards` entry** carries the VM's port 80 to the Mac's port 8000 on localhost, for all the names. It is 8000, not 80, because Lima did not forward the Mac's privileged port 80; Caddy matches the name and ignores the port. Caddy is inside the VM, so it can reach any VM port: a new name needs no new forward.
- **The Mac's `/etc/hosts`** points each name at `127.0.0.1`. `./bootstrap.sh` (and so `./update-vm.sh`) adds every `http://<name>.devvm` it finds in `provision/caddy.sh`, and asks for your sudo password only when a name is missing.
- **Plain HTTP only** (`http://` in front of each name), so there are no certificates to trust.
- The old `localhost:PORT` addresses still work.

### Adding a project

1. **Give the project a port of its own** that no other project uses, and make its dev server fail rather than silently move to the next free port when the port is taken. For Vite, in `vite.config.ts`:

   ```ts
   server: {
     port: 5186,
     strictPort: true,
     allowedHosts: ['.devvm'], // Vite refuses unknown Host headers (403) without this
   },
   ```

   Other servers: set the port in their config or start script. If a server builds absolute links or opens a websocket to itself (Hugo does both), tell it its public address is `http://<name>.devvm:8000`, as `blog-serve` does.

2. **Add a block to the Caddyfile in `provision/caddy.sh`** (search for `http://sonar.devvm`). The block must start with a tab, like the others:

   ```
   http://myapp.devvm {
   	reverse_proxy localhost:5186
   }
   ```

3. **On the Mac, run `./update-vm.sh`.** It restarts the VM with the new Caddyfile and adds `myapp.devvm` to `/etc/hosts`.

4. **Start the dev server in the VM** and open http://myapp.devvm:8000 on the Mac. Then add the name to the table above.

To try a route without a restart, edit `/etc/caddy/Caddyfile` in the VM and run `sudo systemctl reload caddy`, then add the same block to `provision/caddy.sh` so the next boot keeps it. If a name shows `502 Bad Gateway`, Caddy is fine but nothing is listening on that port: start the dev server. If the browser can't find the name at all, it is missing from the Mac's `/etc/hosts`. If every name hangs, something else on the Mac holds port 8000, so Lima could not take it: `sudo lsof -nP -iTCP:8000 -sTCP:LISTEN` on the Mac shows what. VS Code did once (see **VS Code**); free the port, then run `./update-vm.sh`, because Lima only sets up the forward at boot.

## Secret scanning

Every commit in the VM is checked for secrets (API keys, tokens, private keys, passwords in connection strings) by [betterleaks](https://github.com/betterleaks/betterleaks) (from the makers of gitleaks) before it is made. If betterleaks finds one, the commit is refused and the output shows the file, the line and the rule, with the secret itself redacted. The main risk it covers is an agent pasting a key into a file and committing it.

`dev.yaml` sets this up in three ways, because no single one reaches every repo:

- **New repos:** `/etc/gitconfig` sets `init.templateDir` to `/usr/local/share/devvm/git-template`, so `git clone` and `git init` copy a `pre-commit` hook into each new repo.
- **Existing repos:** on every boot, each repo under `~/projects` that has no `pre-commit` hook gets the same hook. A repo that already has a different `pre-commit` hook (lefthook, the pre-commit framework, or a hand-written one) is left alone. The boot prints a `!` warning naming it, because commits there are **not** scanned.
- **Husky repos:** Husky sets `core.hooksPath`, so git ignores `.git/hooks` there. Husky v9 runs `~/.config/husky/init.sh` before each of its hooks, and the boot adds the scan there. This only applies to repos that have a `.husky/pre-commit` file.

Each hook is a one-line script that calls `/usr/local/bin/devvm-secret-scan`, so a change to the scan reaches every repo on the next boot. To check that a repo is covered, look for `.git/hooks/pre-commit`, or for `.husky/pre-commit` in a Husky repo.

**False positives.** Add a `betterleaks:allow` comment on the line, or add the `Fingerprint` from the output to `.betterleaksignore` at the repo root and commit that file. A `.betterleaks.toml` at the repo root changes the rules for that repo; the scan passes it with `--config`, since betterleaks does not load it on its own. Its syntax is not gitleaks': exemptions are Expr `filter`s, not `[[allowlists]]`.

**Scan a repo's history** (the hook only checks new commits):

```bash
betterleaks git --redact -v   # add --config .betterleaks.toml if the repo has one
```

**Limits:**

- `git commit --no-verify` skips every hook, this one included. The user-wide `CLAUDE.md` tells Claude not to use it unless you ask.
- If betterleaks is not installed (its download failed during `./update-vm.sh`), the hook prints a warning and lets the commit through **unscanned**. Re-run `./update-vm.sh` to fix it.
- A repo that sets `core.hooksPath` to its own folder (a native hook, not Husky) makes git skip `.git/hooks`, so the scan does not run unless that folder's `pre-commit` calls `devvm-secret-scan`. The `apply-project-standards` skill adds that line; `standards-check` flags a hook without it.
- Nothing scans commits made on the Mac.
- As a backstop, turn on GitHub's secret scanning with push protection in each repo's **Settings → Advanced Security**. It is free for public repos and blocks a push that contains a known token format.

## SonarQube

`dev.yaml` runs [SonarQube Community Build](https://www.sonarsource.com/products/sonarqube/) in Docker and installs the scanner CLI, so any repo can be checked for bugs, code smells and security issues with one command. The main use is as a quality gate in the sdlc-pipeline's **Verify** step, so agents have to fix what it finds before they report done.

| | |
|---|---|
| Server | `sonarqube` container, http://sonar.devvm:8000 on the Mac (or http://localhost:9000) |
| Scanner | `sonar-scanner`, on `PATH` |
| `sonar-check` | Wrapper that scans the current repo and fails when the quality gate fails |

### One-time setup

Do this once per VM. A rebuild (`limactl delete`) wipes SonarQube's database along with everything else, so repeat it after one.

1. Open http://sonar.devvm:8000 on the Mac, log in as `admin` / `admin`, and set a new password when asked.
2. **My Account → Security → Generate Tokens.** Type **User token**, any name, choose an expiry. A user token carries the admin's *Create Projects* permission, which is what lets the first scan of a repo create its project. A project analysis token can't do that.
3. Store it in the VM, readable only by you:

   ```bash
   mkdir -p ~/.config/sonar && (umask 077; cat > ~/.config/sonar/token)   # paste the token, then Enter and Ctrl-D
   ```

4. Check it from any repo:

   ```bash
   cd ~/projects/current/<repo> && sonar-check
   ```

Anyone can read the server without logging in (the container sets `SONAR_FORCEAUTHENTICATION=false`), so agents can list issues with a plain `curl "http://localhost:9000/api/issues/search?components=<key>&resolved=false"`. Only scanning needs the token. A container created before this setting doesn't have it: turn off **Administration → Configuration → General Settings → Security → Force user authentication** instead.

### Scanning a repo

`sonar-check` runs from anywhere in a git repo and scans the whole repo. It:

- uses `sonar.projectKey` from `sonar-project.properties` if the repo has one, otherwise the repo's directory name;
- creates the project in SonarQube on the first scan;
- waits for the quality gate and exits non-zero if the gate fails. When it fails, it prints the failed gate conditions and the open issues in new code as `file:line rule message`, so an agent can fix them without opening the dashboard;
- passes any extra arguments through to `sonar-scanner`, for example `sonar-check -Dsonar.exclusions=dist/**`.

A repo needs no config to start. Add a `sonar-project.properties` at its root when you need to narrow the scan or feed in test coverage:

```properties
sonar.sources=src
sonar.tests=test
sonar.exclusions=**/generated/**
# sonar.javascript.lcov.reportPaths=coverage/lcov.info
# sonar.coverage.jacoco.xmlReportPaths=build/reports/jacoco/test/jacocoTestReport.xml
```

The scanner writes a `.scannerwork/` directory in the repo. Add it to the repo's `.gitignore`.

**Run `sonar-check` once on the base branch when you start using it on a repo.** The quality gate judges *new code*: by default, anything changed since the first scan. The first scan sets that baseline and passes regardless, so if it happens in the middle of a pipeline run, that run's changes get a free pass.

### In the sdlc-pipeline

Every pipeline agent (implementer, qa, senior-dev) runs the **Verify** command from the repo's `.claude/sdlc-profile.md` and has to make it pass. Append `sonar-check` to it:

```markdown
- **Verify:** `pnpm test && sonar-check`.
  Every agent runs this to prove its work and pastes the output. A failed SonarQube quality gate
  is a failed Verify: fix the listed issues, don't suppress them with `// NOSONAR`.
```

Put it last. Tests are faster and fail first, and a scan takes from 30 seconds to a few minutes.

To make reviewers judge Sonar findings as well as run the scan, add a line under the profile's **Review checklist → Code review**, such as: *SonarQube quality gate passes on new code; any `NOSONAR` needs a comment saying why.*

### Limits of the Community Build

- **No branch or pull-request analysis.** Each repo has one analysis, and every scan replaces it, whichever branch you are on. That's fine for one person working one branch at a time.
- **About 2–3 GB of RAM** while running. If the VM feels tight, run `docker stop sonarqube`; it stays stopped until `docker start sonarqube`, even across reboots. `sonar-check` says so if it can't reach the server.
- **Version bumps need a rebuild.** It uses the embedded H2 database, which SonarQube can't upgrade in place. The rebuild that a `SONARQUBE_VERSION` bump already requires starts it fresh. Redo the one-time setup afterwards.

## Project standards

`~/projects/CLAUDE.md` holds the standards every project under `~/projects` follows. Claude Code reads `CLAUDE.md` files in parent directories, so every session in a project picks them up. Like `~/.claude/CLAUDE.md`, it is rewritten on every boot from `files/projects-CLAUDE.md`: change the standards there. Detail for one repo goes in that repo's own `CLAUDE.md`.

| Standard | Why |
|---|---|
| Run the tests and `sonar-check` before reporting work as done | An agent's "done" should mean the checks passed, not that the code was written. |
| List SonarQube issues with an unauthenticated `curl` to `api/issues/search` | `sonar-check` prints only new-code issues, and only when the gate fails. The server allows anonymous reads (see SonarQube), so an agent needs no token to see the rest. |
| Formatting and linting run inside the normal test/verify command: format and auto-fix first, then fail on what is left | If formatting only happens at commit, the tests and `sonar-check` run on code that the hook then rewrites, and lint failures turn up after the work was reported done. In the build, they happen as a matter of course, with no extra step to forget. |
| In CI (`CI` set), the build only checks and never rewrites | CI must fail on unformatted code. If it formatted, it would pass and the fix would never reach the repo. |
| The format-on-commit hook stays, as a backstop | It catches edits made outside the build, such as a quick fix in the IDE. |
| Use `./run` when the repo has one | It holds the repo's own way to set up, serve and build, so nobody has to guess the commands. |
| Pin dependency versions; Renovate bumps them | Builds are reproducible, and every upgrade is a reviewed PR, not a surprise in the next install. |
| `shellcheck` for shell scripts, `hadolint` for Dockerfiles | Both catch common, quiet bugs (unquoted variables, unpinned base images). The VM installs both, and `limactl start` checks for them. |
| GitHub secret scanning with push protection on in every repo | The commit hook only runs in the VM. Push protection also covers commits made on the Mac (see [Secret scanning](#secret-scanning)). |
| Java: Spotless, PMD and SpotBugs (or Error Prone) in the build | They go in each project's Gradle or Maven build, not the VM, so CI and any other machine run the same checks. Gradle's plugins hook into `check`. Outside CI, `compileJava` depends on `spotlessApply`; in Maven, `spotless:apply` is bound to `process-sources` in a profile that is off when `CI` is set. |
| Java: build with `./gradlew` or `./mvnw` | The wrapper pins the build tool's version in the repo. A system Gradle or Maven can differ from what CI uses. |
| JS/TS: pnpm, ESLint (or oxlint, if you prefer), Prettier, strict TypeScript | pnpm is the house package manager. It is enforced at three levels: the root `package.json`'s `devEngines.packageManager` makes `npm install` fail on any machine (Node 25+ has no Corepack, so `packageManager` alone does not), deny rules in `~/.claude/settings.json` refuse Claude's `npm`/`npx` calls, and a shell `npm()` guard blocks installs where a `pnpm-lock.yaml` exists. oxlint is a much faster linter with fewer rules and plugins. `strict` catches null and type errors at compile time. |
| JS/TS: the `test` script runs `eslint --fix` (or `oxlint --fix`), `prettier --write`, then the tests; CI runs a check-only `lint` script | The same format-in-the-build rule as above. It is part of `test` itself, not a `pretest` script, because pnpm may not run pre/post scripts. |
| JS/TS: `pnpm audit` after adding a dependency | It catches a known-vulnerable package when it is added, not months later. |

These are instructions to Claude, not checks. Nothing enforces them in an existing repo until its build is set up this way.

**Applying them to a repo.** In a Claude Code session in the repo, say "apply project standards". That runs the `apply-project-standards` skill, which `dev.yaml` installs into `~/.claude/skills` on every boot. It runs `standards-check`, fixes each gap with a fixed recipe (the Gradle and Maven plugin setup, the `package.json` scripts, hooks, `renovate.json`), gets the build green after each part, and reports what it changed. When a new checker finds many existing violations, it stops and asks rather than fixing hundreds of lines or turning the checker off. It asks before changing GitHub settings and does not commit unless asked. The skill holds only the recipes; the rules stay in `~/projects/CLAUDE.md`.

**Checking a repo.** `standards-check` (in the VM's `PATH`) lists one gap per line and exits 1 if there are any. It is read-only, so it is also a quick way to see how far a repo is from the standards:

```bash
for r in ~/projects/current/*/; do echo "== $r"; standards-check "$r"; done
```

It is a heuristic: "has PMD" means the word appears in the build, not that PMD runs. A private repo on a free GitHub plan cannot have push protection, so it gets a `note:`, not a gap.

## Dev database (Postgres)

`dev.yaml` runs Postgres in Docker so you and Claude can work with real data while coding: read the actual schema, try a query before it goes into code, run a migration and check the result. It is separate from the Supabase stack (port 54322) and only for local data. **Never point these settings at production.**

| | |
|---|---|
| Server | `postgres` container, `localhost:5432` (forwarded to the Mac at the same address) |
| Database | `dev`, owned by `dev_rw` |
| `dev_ro` | For exploring. Can read every table in every database on the server (`pg_read_all_data`) and can't change anything; its sessions also start read-only. |
| `dev_rw` | For migrations and seed data. Owns `dev` and can create more databases, for example one per project. Not a superuser. |
| Client | `psql`, `pg_dump` and friends, from the PostgreSQL project's apt repo at the server's major version (Ubuntu's own package is 16, too old for an 18 server) |

Connect by service name. No passwords to type or paste:

```bash
psql service=dev_ro                      # explore
psql service=dev_rw                      # change things
psql "service=dev_ro dbname=myproject"   # another database on the same server
```

The services are defined in `/etc/postgresql-common/pg_service.conf`. The passwords are generated once per VM, kept in `/etc/devdb/` (root only), and copied into `~/.pgpass`. Provisioning replaces only the two `localhost:5432` lines there, so your other entries survive.

Tools that don't read `~/.pgpass`, like Flyway or a JDBC URL, need the password passed in. Read it from `~/.pgpass` at run time rather than putting it in a repo:

```bash
FLYWAY_URL=jdbc:postgresql://localhost:5432/dev FLYWAY_USER=dev_rw \
FLYWAY_PASSWORD="$(awk -F: '$4=="dev_rw"{print $5}' ~/.pgpass)" flyway migrate
```

### Telling Claude about it

Claude only uses the database if it knows it's there. Add something like this to a repo's `CLAUDE.md`:

> Local Postgres: explore with `psql service=dev_ro` (read-only). Apply migrations and seed data with `psql service=dev_rw`, only when the task calls for it. This project's database is `<name>`.

### Notes

- **Every boot re-applies the roles, grants and passwords**, so a re-provision or a fresh volume ends up the same. The data itself lives in the `postgres_data` Docker volume and survives restarts, but not a rebuild.
- **To free memory**, run `docker stop postgres`. It stays stopped until `docker start postgres` or the next provision.
- **A major version bump needs a rebuild** (or a dump and restore), because Postgres can't open an older major's data directory. The same pin sets the client's major version, so the two stay matched. Renovate holds major bumps for approval anyway (see **Renovate**).
- **Superuser access**, when you need it: `docker exec -it postgres psql -U postgres`.

## The rule

> **If something is installed in the VM and not in `dev.yaml` (or the `provision/` and `files/` it points at), that is a bug there.**

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

The catch: a restart reads the instance's own copy, `~/.lima/dev/lima.yaml`, which was taken from `dev.yaml` when the VM was created. Editing `dev.yaml`, `provision/` or `files/` here changes nothing until that copy is replaced. On the host:

```bash
./update-vm.sh
```

It pulls, drops the shared SSH connection, stops the VM, writes `dev.yaml` over `~/.lima/dev/lima.yaml` with `limactl template copy --embed` (which copies in every `provision/` and `files/` file the steps point at; a plain `cp` would leave paths that do not resolve from `~/.lima`), and runs `./bootstrap.sh`, which starts the VM and rewrites the `~/.ssh/config` block. Last, it lists this boot's provision warnings (lines starting `! `), since a best-effort step that skipped something does not fail the boot.

Each provision step skips work it already did (the skills step installs only skills whose `SKILL.md` is missing), so a restart re-runs them quickly. Two steps also update on every boot: plugins move to their latest version, and `npx skills update -g` re-copies any skill that changed on GitHub (overwriting local edits to it). Check the result:

```bash
limactl shell dev -- ls ~/.claude/skills
```

A skill that fails to install does not fail the boot, so the `ls` is the check — a missing directory means a skipped skill. Install it by hand with the command in `provision/skills.sh`. Start a new Claude Code session afterwards, because skills load at session start.

The user-wide `~/.claude/CLAUDE.md` (instructions every Claude Code session in the VM reads) is also rewritten on every boot, from `files/CLAUDE.md`. Add or change an instruction there, not in the VM, or the next restart undoes it. The Mac has its own `~/.claude/CLAUDE.md` for sessions run on the host; keep the two in step.

`~/projects/CLAUDE.md` works the same way, from `files/projects-CLAUDE.md`; see [Project standards](#project-standards).

Plugins (currently `sdlc-pipeline` and `ponytail`) are different: the provision only writes them into `~/.claude/settings.json` as `extraKnownMarketplaces` and `enabledPlugins`, because the `claude` CLI install is best-effort and may not have happened yet. Enabling a plugin there does not install it. So once a `claude` CLI exists (the provisioned `~/.local/bin/claude`, or the desktop app's own copy), every boot also adds a missing marketplace, installs a missing plugin, and runs `claude plugin marketplace update` and `claude plugin update` (user scope) for the rest, so a restart installs a newly listed plugin and brings the others to their latest version. The marketplace entries also set `autoUpdate`, which checks again at each session start. Both act only when the plugin's `plugin.json` version has been bumped. Project-scope installs (made with `--scope project` inside a repo) are not touched; update those from inside that repo. Check with `/plugin` in a session in the VM; if one is missing, run `claude plugin marketplace add <owner>/<repo>` and `claude plugin install <plugin>@<marketplace>` there, with the values from the plugins list in `provision/plugins.sh` (for example `prule/sdlc-pipeline` and `sdlc-pipeline@sdlc-pipeline`).

Use the full rebuild above instead when a change is not additive: removing a package, changing a version pin, or changing the disk.

### Renovate

[Renovate](https://docs.renovatebot.com/) opens a PR when a new version is released for Node, pnpm, OpenSpec, the Supabase CLI, the `skills` CLI, SonarQube, the SonarScanner CLI or Postgres. It needs the Renovate GitHub App installed on this repo.

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
- **Ports.** Lima auto-forwards guest ports bound to `0.0.0.0`. Ports bound to `127.0.0.1` *inside* the guest need a `portForwards` entry. `dev.yaml` declares the known ones (5173/4173/5174, 54321–54324, 9000 for SonarQube, 5432 for the dev database, 80 for Caddy); the robust fix is still `server: { host: true }` in `vite.config.ts`.
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

Each of those is marked `GONE:` at the point in `dev.yaml` or `provision/` where the ported step used to be, so the omissions are reviewable rather than forgotten.
