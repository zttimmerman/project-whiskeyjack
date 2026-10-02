#!/usr/bin/env bash
# playtest-branch.sh — playtest any branch in a disposable review worktree,
# without touching your own working copy or editor.
#
# Usage:
#   scripts/tools/playtest-branch.sh <branch-or-ref> [--play|--editor|--no-launch]
#   scripts/tools/playtest-branch.sh --status
#   scripts/tools/playtest-branch.sh --done
#
# The review worktree lives at <main repo parent>/project-whiskeyjack-review,
# detached at origin/<branch> (or the local ref). It is disposable: local
# changes in it are discarded on every run. Override the engine with GODOT=/path.
set -euo pipefail

die() { echo "playtest: $*" >&2; exit 1; }
# The version probes and the import run under a limit (a hung Godot fails instead of idling forever);
# the launched game or editor does not.
source "$(dirname "${BASH_SOURCE[0]}")/godot_timeout.sh" || die "missing scripts/tools/godot_timeout.sh"

COMMON_DIR=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
  || die "run this from inside the project repo"
MAIN_REPO=$(dirname "$COMMON_DIR")
REVIEW="$(dirname "$MAIN_REPO")/project-whiskeyjack-review"
git_main() { git -C "$MAIN_REPO" "$@"; }

review_registered() {
  git_main worktree list --porcelain | grep -qxF "worktree $REVIEW"
}

case "${1:-}" in
  ""|-h|--help)
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  --status)
    if review_registered && [ -d "$REVIEW" ]; then
      echo "review worktree: $REVIEW"
      echo "at: $(git -C "$REVIEW" log -1 --format='%h %s (%cr)')"
      dirty=$(git -C "$REVIEW" status --porcelain | wc -l | tr -d ' ')
      echo "local changes: $dirty file(s)"
    else
      echo "no review worktree ($REVIEW)"
    fi
    exit 0 ;;
  --done)
    review_registered || { echo "no review worktree registered at $REVIEW"; git_main worktree prune; exit 0; }
    # Only ever remove the exact review path.
    [ "$(basename "$REVIEW")" = "project-whiskeyjack-review" ] || die "refusing: unexpected path $REVIEW"
    git_main worktree remove --force "$REVIEW"
    git_main worktree prune
    echo "removed $REVIEW"
    # The review copies' own user:// folders (override.cfg names them "REVIEW <ref> · ..."); only
    # folders with that exact prefix, never the human's "Project Whiskeyjack".
    for d in "$HOME/Library/Application Support/Godot/app_userdata/REVIEW "*; do
      [ -d "$d" ] && rm -rf "$d" && echo "removed review saves: $(basename "$d")"
    done
    exit 0 ;;
  -*) die "unknown option $1 (see --help)" ;;
esac

REF=$1; MODE=${2:---play}
case "$MODE" in --play|--editor|--no-launch) ;; *) die "unknown mode $MODE" ;; esac

# 1. Fetch and resolve the ref (prefer origin/<branch>).
git_main fetch --quiet origin 2>/dev/null || echo "playtest: fetch failed (offline?), using local refs"
if git_main rev-parse --verify --quiet "refs/remotes/origin/$REF^{commit}" >/dev/null; then
  TARGET="origin/$REF"
elif git_main rev-parse --verify --quiet "$REF^{commit}" >/dev/null; then
  TARGET="$REF"
else
  die "no such branch or ref: $REF"
fi
SHA=$(git_main rev-parse "$TARGET^{commit}")

if review_registered && [ -d "$REVIEW" ]; then
  discard=$( { git -C "$REVIEW" status --porcelain --untracked-files=no; git -C "$REVIEW" clean -ndx -e .godot -e override.cfg; } )
  if [ -n "$discard" ]; then
    echo "playtest: discarding local changes in the review worktree:"
    echo "$discard" | sed 's/^/  /'
  fi
  git -C "$REVIEW" reset --quiet --hard
  git -C "$REVIEW" clean --quiet -fdx -e .godot
  git -C "$REVIEW" checkout --quiet --detach "$SHA"
else
  [ -e "$REVIEW" ] && die "$REVIEW exists but is not a registered worktree; move it aside"
  git_main worktree prune
  git_main worktree add --quiet --detach "$REVIEW" "$SHA"
fi

# Label the copy: override.cfg renames the project, so its editor and game windows read
# "REVIEW <ref>" and can't be mistaken for the human's own editor, and (user:// being keyed by the
# project name) its saves stay out of the human's save.json. Rewritten on every run.
printf '[application]\n\nconfig/name="REVIEW %s · Project Whiskeyjack"\n' "$TARGET" >"$REVIEW/override.cfg"

# 2. Pick the Godot binary from project.godot's config/features.
VER=$(sed -n 's/^config\/features=PackedStringArray("\([0-9][0-9.]*\)".*/\1/p' "$REVIEW/project.godot" | head -1)
if [ -n "${GODOT:-}" ]; then
  G=$GODOT
else
  # First installed Godot whose --version matches the project's major.minor, so the choice
  # survives app moves (/Applications/Godot.app is whichever version is current).
  [ -n "$VER" ] || die "can't read config/features from $REVIEW/project.godot; set GODOT=/path/to/Godot"
  G=""
  for cand in /Applications/Godot.app /Applications/Godot-"$VER"*.app "$HOME"/Applications/godot-"$VER"*/Godot.app; do
    bin="$cand/Contents/MacOS/Godot"
    if [ -x "$bin" ] && with_timeout GODOT_TIMEOUT_RUN 60 "playtest: $bin --version" "$bin" --version 2>/dev/null | grep -q "^$VER\."; then G=$bin; break; fi
  done
  [ -n "$G" ] || die "no installed Godot $VER found (looked in /Applications and ~/Applications); set GODOT=/path/to/Godot"
fi
[ -x "$G" ] || die "Godot binary not found or not executable: $G"
export GODOT_AI_DISABLE_TELEMETRY=true
GVER=$(with_timeout GODOT_TIMEOUT_RUN 60 "playtest: $G --version" "$G" --version 2>/dev/null | head -1 || echo unknown)

# 3. Headless import so the first launch doesn't stall.
echo "playtest: importing (first run can take a minute)..."
LOG=$(mktemp -t playtest-import)
if with_timeout GODOT_TIMEOUT_IMPORT 900 "playtest: import" "$G" --headless --path "$REVIEW" --import </dev/null >"$LOG" 2>&1; then :
elif [ $? -eq 124 ]; then die "$(tail -1 "$LOG")"
else echo "playtest: import exited non-zero (see $LOG)"; fi
errors=$(grep -c 'ERROR' "$LOG" || true)
echo "playtest: import done, $errors ERROR line(s) (log: $LOG)"

# 4. Banner and detached launch.
echo "== $TARGET @ $(git -C "$REVIEW" log -1 --format='%h %s') | Godot $GVER (project $VER) =="
[ "$MODE" = "--no-launch" ] && { echo "playtest: --no-launch, ready at $REVIEW"; exit 0; }
ARGS=(--path "$REVIEW"); [ "$MODE" = "--editor" ] && ARGS+=(-e)
nohup "$G" "${ARGS[@]}" >/dev/null 2>&1 &
echo "playtest: launched ${MODE#--} (PID $!) at $REVIEW"
echo "playtest: clean up later with: $0 --done"
