# devvm

One Linux VM for every project, driven by the Claude Code desktop app over SSH.

Replaces the per-project `.devcontainer/` setup. Rationale and trade-offs:
[One VM Instead of Seven Dev Containers](https://prule.github.io/pauls-blog/post/coding/2026/one-vm-instead-of-seven-devcontainers/).

```
macOS host (thin)                      Lima VM "dev" (Ubuntu 24.04 arm64)
├── Claude Code desktop app ───SSH───► ├── Node 26.7.0, pnpm 12.4.2, OpenSpec
├── WebStorm (native)                  ├── Temurin 25 (+21), Playwright
├── Browser → localhost:5173           ├── Docker Engine → supabase-local-platform
├── Xcode / iOS Simulator              └── ~/.claude, ~/.config/gh (one login)
└── Time Machine (excludes ~/.lima)
                                       
    ~/projects/current ◄── virtiofs, writable ──► /Users/paulrule/projects/current
    (host: WebStorm reads/edits)                  (VM: agent, pnpm, builds)
```

## Files

| | |
|---|---|
| `dev.yaml` | The environment. Lima config + all provisioning. **The only source of truth.** |
| `bootstrap.sh` | Host-side. Creates the VM, writes the `lima-dev` SSH config block, excludes `~/.lima` from Time Machine. |
| `setup-github.sh` | Run once in the VM. VM-only SSH key + `gh auth login`. Interactive, so it can't live in `dev.yaml`. |
| `migrate-repo.sh` | Run in the VM, once per repo. Drops `.devcontainer/`, pins Node, wipes macOS-built `node_modules`, reinstalls. |

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

## The two rules

> **pnpm runs in the VM only. Never on the host.**

`~/projects/current` is shared writable, so `node_modules` is shared too — and native binaries (esbuild, rollup, sharp, better-sqlite3) belong to whichever OS installed last. The dev containers kept `node_modules` on per-project volumes precisely to stop this mixing; the shared mount gives that protection up in exchange for host-native WebStorm. Running `pnpm install` on the Mac will break every build in the VM until you reinstall there.

Same applies to anything that writes `node_modules`: let WebStorm *read* the project, but don't let it run installs or npm scripts on the host.



> **If something is installed in the VM and not in `dev.yaml`, that is a bug in `dev.yaml`.**

`vmType: vz` means no snapshots (`limactl snapshot` is QEMU-only). There is no restore point — recovery is `limactl delete dev && ./bootstrap.sh`, which only works if this file is complete. So never fix a missing package with a bare `sudo apt install` in the VM; add it here and reprovision.

Nothing in the VM is backed up. Everything that matters is in git and pushed.

## Bumping the toolchain

Edit `param:` in `dev.yaml`, then:

```bash
limactl stop dev && limactl delete dev && ./bootstrap.sh
```

This bumps all ~40 projects at once. That is the intent, and also the risk — it's the cost of dropping per-repo Dockerfiles. Do it deliberately, not incidentally.

## Gotchas

- **Expect virtiofs to be slower.** `pnpm install`, the TS language server, Vite HMR and Playwright all cross the mount now. This is the known, accepted cost of running WebStorm natively on the host. If a specific project becomes painful, that one project's `node_modules` can be bind-mounted to a VM-local directory — at the price of WebStorm losing import resolution for it.
- **Paths are identical on both sides.** `mountPoint` mirrors the host path, so `/Users/paulrule/projects/current/foo` means the same thing in WebStorm and in a Claude Code session. `~/projects/current` in the VM is a symlink to it.
- **Time Machine.** `~/.lima` is excluded, but your code is on the host now, so it's backed up properly again. Worth excluding the `node_modules` trees so they don't bloat every snapshot.
- **Java is the exception to "one version".** `JAVA_VERSIONS: "25 21"` — 25 is the default, 21 is present because several `laptime-insights` modules pin `jvmToolchain(21)`, and a missing toolchain JDK makes Gradle auto-provision mid-build or fail. Drop 21 once nothing asks for it.
- **`param:`, not `env:`.** Provision scripts only see `param:` values, as `$PARAM_<Key>`. `env:` sets the login environment and is invisible to provisioning — an easy and silent-looking mistake that actually aborts the provision under `set -u`.
- **Ports.** Lima auto-forwards guest ports bound to `0.0.0.0`. Ports bound to `127.0.0.1` *inside* the guest need a `portForwards` entry. `dev.yaml` declares the known ones (5173/4173/5174, 54321–54324); the robust fix is still `server: { host: true }` in `vite.config.ts`.
- **Docker group.** The first login after provisioning may not have the `docker` group yet. `limactl stop dev && limactl start dev` fixes it.
- **One shared folder, not the whole home directory.** `~/projects/current` is writable from the VM; `~/Documents`, `~/.ssh`, the keychain and `~/Library` are not. The agent can damage the repos — all in git, all pushed — and nothing else. This is the same posture the dev containers had, since a devcontainer bind-mounts its workspace by default.
- **No agent forwarding, on purpose.** `bootstrap.sh` strips `ForwardAgent yes` if a regenerated SSH block ever introduces one. The VM has its own GitHub key.
- **`@mention` files** doesn't work in desktop-app SSH sessions. File attachment does. This is the one real day-to-day loss.
- **Xcode / iOS stays on the host.** Nothing simulator-related can move into the VM.

## What this deleted

Seven `.devcontainer/` directories (~1,500 lines), seven `docs/DevContainers.md`, Docker Desktop (~47 GB), and every workaround that existed only because the environments were separate: `CLAUDE_CONFIG_DIR`, `GH_CONFIG_DIR`, `PLAYWRIGHT_SKIP_BROWSER_GC`, `--add-host=host.docker.internal`, the shared `/cache` volume convention, the `pnpm config set store-dir` double-write under two `XDG_CONFIG_HOME` values, and the "never mount a volume at `PNPM_HOME`" rule.

Each of those is marked `GONE:` at the point in `dev.yaml` where the ported step used to be, so the omissions are reviewable rather than forgotten.
