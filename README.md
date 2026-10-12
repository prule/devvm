# devvm

One Linux VM for every project, driven by the Claude Code desktop app over SSH.

Replaces the per-project `.devcontainer/` setup. Rationale and trade-offs:
[One VM Instead of Seven Dev Containers](https://prule.github.io/pauls-blog/post/coding/2026/one-vm-instead-of-seven-devcontainers/).

```
macOS host (thin)                      Lima VM "dev" (Ubuntu 24.04 arm64)
├── Claude Code desktop app ───SSH───► ├── ~/projects/current/…  all 40 repos
├── JetBrains Gateway ───────SSH───►   ├── WebStorm backend (Gateway installs)
│   (thin client only)                 ├── Node 26.7.0, pnpm 12.4.2, OpenSpec
├── Browser → localhost:5173           ├── Temurin 25 (+21), Playwright
├── Xcode / iOS Simulator              ├── Docker → supabase-local-platform
└── Time Machine (excludes ~/.lima)    └── ~/.claude, ~/.config/gh (one login)

Two thin clients on the Mac, one box doing the work. No shared folders.
```

## Files

| | |
|---|---|
| `dev.yaml` | The environment. Lima config + all provisioning. **The only source of truth.** |
| `bootstrap.sh` | Host-side. Creates the VM, writes the `lima-dev` SSH config block, excludes `~/.lima` from Time Machine. |
| `setup-github.sh` | Run once in the VM. VM-only SSH key + `gh auth login`. Interactive, so it can't live in `dev.yaml`. |
| `migrate-repo.sh` | Run in the VM, once per repo. Clones, drops `.devcontainer/`, pins Node, installs. |

## Quickstart

```bash
./bootstrap.sh
limactl copy setup-github.sh dev:/tmp/ && limactl shell dev -- bash /tmp/setup-github.sh
```

Then in the Claude Code desktop app: environment dropdown → **+ Add SSH connection** → host `lima-dev`, leave port and identity file empty (they come from `~/.ssh/config`). Claude Code installs itself on the VM on first connect.

Verify:

```bash
limactl shell dev -- bash -lc 'node -v; pnpm -v; openspec --version; java -version; docker run --rm hello-world'
```

`java -version` must report **25**. Two JDKs are installed and Debian
alternatives prefer the highest available, so this is worth actually reading
rather than glancing at.

## WebStorm

```bash
brew install --cask jetbrains-gateway
```

Gateway → **SSH** → `lima-dev` → pick a project under `~/projects/current`. It downloads the WebStorm backend into the VM on first connect; the thin client is the only JetBrains process on the Mac.

This is the same architecture the dev containers used via `"jetbrains": { "backend": "WebStorm" }` — IDE backend next to the code, GUI on the host.

It is also why there is no shared folder. A writable mount of `~/projects/current` would put `node_modules` on both sides of the boundary, where native binaries (esbuild, rollup, sharp) belong to whichever OS installed last — exactly what the containers' per-project `node_modules` volumes prevented. Keeping `node_modules` VM-local instead left the host IDE unable to resolve an import. Moving the IDE to the code's side of the boundary dissolves the problem rather than trading around it, and JetBrains wants local disk for the backend anyway — network filesystems are explicitly unsupported.

`dev.yaml` provisions the two things the backend needs from the OS: a few X/font libraries, and `fs.inotify.max_user_watches = 524288` (below roughly that, the IntelliJ platform stops watching files and falls back to recursive rescans).

## The rule

> **If something is installed in the VM and not in `dev.yaml`, that is a bug in `dev.yaml`.**

`vmType: vz` means no snapshots (`limactl snapshot` is QEMU-only). There is no restore point — recovery is `limactl delete dev && ./bootstrap.sh`, which only works if this file is complete. So never fix a missing package with a bare `sudo apt install`; add it here and reprovision.

Nothing in the VM is backed up. Everything that matters is in git — so push before you stop for the day. That is an obligation, not a shrug.

## Bumping the toolchain

Edit `param:` in `dev.yaml`, then:

```bash
limactl stop dev && limactl delete dev && ./bootstrap.sh
```

This bumps all ~40 projects at once. That is the intent, and also the risk — it's the cost of dropping per-repo Dockerfiles. Do it deliberately, not incidentally.

## Gotchas

- **Sizing.** 6 CPU / 14 GB, up from 4/12, because the VM now runs a full IDE backend alongside the agent and the builds. JetBrains asks 2+ cores and 4 GB+ for the backend alone. This is the first knob to turn if it feels tight.
- **No host mounts.** `mounts: []`. Moving files: `limactl copy`, or git. See **WebStorm** above for why.
- **Java is the exception to "one version".** `JAVA_VERSIONS: "25 21"` — 25 is the default, 21 is present because several `laptime-insights` modules pin `jvmToolchain(21)`, and a missing toolchain JDK makes Gradle auto-provision mid-build or fail. Drop 21 once nothing asks for it.
- **`param:`, not `env:`.** Provision scripts only see `param:` values, as `$PARAM_<Key>`. `env:` sets the login environment and is invisible to provisioning — an easy and silent-looking mistake that actually aborts the provision under `set -u`.
- **Ports.** Lima auto-forwards guest ports bound to `0.0.0.0`. Ports bound to `127.0.0.1` *inside* the guest need a `portForwards` entry. `dev.yaml` declares the known ones (5173/4173/5174, 54321–54324); the robust fix is still `server: { host: true }` in `vite.config.ts`.
- **Docker group.** The first login after provisioning may not have the `docker` group yet. `limactl stop dev && limactl start dev` fixes it.
- **No agent forwarding, on purpose.** `bootstrap.sh` strips `ForwardAgent yes` if a regenerated SSH block ever introduces one. The VM has its own GitHub key.
- **`@mention` files** doesn't work in desktop-app SSH sessions. File attachment does. This is the one real day-to-day loss.
- **Xcode / iOS stays on the host.** Nothing simulator-related can move into the VM.

## What this deleted

Seven `.devcontainer/` directories (~1,500 lines), seven `docs/DevContainers.md`, Docker Desktop (~47 GB), and every workaround that existed only because the environments were separate: `CLAUDE_CONFIG_DIR`, `GH_CONFIG_DIR`, `PLAYWRIGHT_SKIP_BROWSER_GC`, `--add-host=host.docker.internal`, the shared `/cache` volume convention, the `pnpm config set store-dir` double-write under two `XDG_CONFIG_HOME` values, and the "never mount a volume at `PNPM_HOME`" rule.

Each of those is marked `GONE:` at the point in `dev.yaml` where the ported step used to be, so the omissions are reviewable rather than forgotten.
