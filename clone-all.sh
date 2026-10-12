#!/usr/bin/env bash
# Clones every project into the VM from repos.tsv. Run INSIDE the VM.
#
#   ./clone-all.sh                 clone everything that is missing
#   ./clone-all.sh --dry-run       show what it would do
#   ./clone-all.sh --filter sdlc   only paths matching a pattern
#   ./clone-all.sh --update        also fetch repos that already exist
#   ./clone-all.sh --root DIR      somewhere other than ~/projects/current
#
# Idempotent: an existing directory is left alone (or fetched with --update).
# Individual failures do not stop the run; they are listed at the end and the
# script exits non-zero.
#
# Requires the VM's own SSH key to be on GitHub — see setup-github.sh. One
# repo (supabase-local-platform) is private, so an unauthenticated run will
# fail on exactly that one.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$HOME/projects/current"
DRY=0; UPDATE=0; FILTER=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --update)  UPDATE=1 ;;
    --filter)  FILTER="${2:?--filter needs a pattern}"; shift ;;
    --root)    ROOT="${2:?--root needs a directory}"; shift ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

[ -f "$HERE/repos.tsv" ] || { echo "repos.tsv missing — run ./make-manifest.sh" >&2; exit 1; }

say()  { printf '%s\n' "$*"; }
step() { printf '  %-44s %s\n' "$1" "$2"; }

cloned=0; skipped=0; fetched=0
declare -a failed=()

# ---------------------------------------------------------------------------
# Clones. Order follows the manifest: top-level first, then nested paths —
# git creates missing parent directories itself, so laptime-insights/ and
# friends need no mkdir.
# ---------------------------------------------------------------------------
say "==> Cloning into $ROOT"
mkdir -p "$ROOT"

while IFS=$'\t' read -r path repo branch; do
  case "$path" in ''|\#*) continue ;; esac
  [ -n "${FILTER}" ] && case "$path" in *"$FILTER"*) ;; *) continue ;; esac

  target="$ROOT/$path"
  if [ -d "$target/.git" ]; then
    if [ "$UPDATE" -eq 1 ]; then
      if [ "$DRY" -eq 1 ]; then step "$path" "would fetch"; else
        if git -C "$target" fetch --quiet --all --prune 2>/dev/null; then
          step "$path" "fetched"; fetched=$((fetched+1))
        else
          step "$path" "FETCH FAILED"; failed+=("$path (fetch)")
        fi
      fi
    else
      step "$path" "exists — skipped"; skipped=$((skipped+1))
    fi
    continue
  fi

  if [ "$DRY" -eq 1 ]; then
    step "$path" "would clone $repo @ ${branch:-default}"; continue
  fi

  # --recurse-submodules is what brings pauls-blog's theme and strength's two
  # submodules along; they are deliberately absent from the manifest.
  if git clone --quiet --recurse-submodules "git@github.com:${repo}.git" "$target" 2>/dev/null; then
    if [ -n "$branch" ] && [ "$branch" != "$(git -C "$target" branch --show-current)" ]; then
      if git -C "$target" checkout --quiet "$branch" 2>/dev/null; then
        step "$path" "cloned, on $branch"
      else
        step "$path" "cloned, but branch '$branch' not found"
        failed+=("$path (branch $branch)")
      fi
    else
      step "$path" "cloned"
    fi
    cloned=$((cloned+1))
  else
    step "$path" "CLONE FAILED ($repo)"
    failed+=("$path ($repo)")
  fi
done < "$HERE/repos.tsv"

# ---------------------------------------------------------------------------
# Worktrees. These are not clones — they are extra checkouts of a repo that
# the loop above already cloned, so they must come after it.
# ---------------------------------------------------------------------------
if [ -f "$HERE/worktrees.tsv" ] && [ -z "$FILTER" ]; then
  say ""
  say "==> Worktrees"
  while IFS=$'\t' read -r path parent branch; do
    case "$path" in ''|\#*) continue ;; esac
    target="$ROOT/$path"; parent_dir="$ROOT/$parent"
    if [ -e "$target" ]; then step "$path" "exists — skipped"; skipped=$((skipped+1)); continue; fi
    # In a dry run the parent was never cloned, so a missing parent is
    # expected rather than a failure.
    if [ "$DRY" -eq 1 ]; then step "$path" "would add worktree of $parent @ $branch"; continue; fi
    if [ ! -d "$parent_dir/.git" ]; then
      step "$path" "parent '$parent' not cloned — skipped"; failed+=("$path (no parent)"); continue
    fi
    if git -C "$parent_dir" worktree add --quiet "$target" "$branch" 2>/dev/null; then
      step "$path" "worktree of $parent @ $branch"; cloned=$((cloned+1))
    else
      step "$path" "WORKTREE FAILED"; failed+=("$path (worktree)")
    fi
  done < "$HERE/worktrees.tsv"
fi

# ---------------------------------------------------------------------------
say ""
say "==> $cloned created, $skipped skipped, $fetched fetched, ${#failed[@]} failed"
if [ "${#failed[@]}" -gt 0 ]; then
  for f in "${failed[@]}"; do say "      ! $f"; done
fi

# The thing most likely to be forgotten, so it is the last thing printed.
if [ -f "$HERE/not-in-git.txt" ]; then
  say ""
  say "==> NOT COVERED BY THIS SCRIPT — these are in no git repo at all:"
  grep -vE '^\s*(#|$)' "$HERE/not-in-git.txt" | sed 's/^/      /'
  say ""
  say "    Copy them from the host deliberately, or decide to drop them:"
  say "      limactl copy -r ~/projects/current/<name> dev:$ROOT/"
fi

say ""
say "    Dependencies are not installed. Per repo: ./migrate-repo.sh <name>"
[ "${#failed[@]}" -eq 0 ]
