#!/usr/bin/env bash
# Attempts on one branch as the repository admin, which stands in for the
# release App. Usage: branch-probe.sh <repo-dir> <branch> <full|ff-only>
# Commits come from branch-commits.env: X the branch's start, L1 and L2
# linear on it, M a merge commit whose first parent is L2.
set -u
cd "$1" || exit 1
B=$2
MODE=$3
R=TylerVigario/ruleset-probe
# shellcheck disable=SC1091
. "$(dirname "$0")/branch-commits.env"
echo "$B ($MODE)  $(date -u +%FT%TZ)"
at() {
  local s
  if s=$(gh api "repos/$R/git/ref/heads/$B" --jq '.object.sha[0:7]' 2>/dev/null); then echo "$s"; else echo gone; fi
}
try() {
  local label=$1
  shift
  if out=$("$@" 2>&1); then
    echo "ALLOWED  $label  -> $B at $(at)"
  else
    echo "REFUSED  $label :: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-400)  -> $B at $(at)"
  fi
}
api_move() { gh api -X PATCH "repos/$R/git/refs/heads/$B" -f sha="$1" -F force="$2"; }

echo "start: $B at $(at)"
try "refs API, force=false, X -> L1 (the release's move)" api_move "$L1" false
[ "$MODE" = ff-only ] && try "git push, fast-forward, X -> L1" git push -q origin "$L1:refs/heads/$B"
[ "$MODE" = ff-only ] && exit 0
try "git push, fast-forward, L1 -> L2" git push -q origin "$L2:refs/heads/$B"
try "git push, fast-forward to merge commit M" git push -q origin "$M:refs/heads/$B"
try "git push --force, back to L1" git push -q --force origin "$L1:refs/heads/$B"
try "refs API, force=true, back to X" api_move "$X" true
try "refs API delete" gh api -X DELETE "repos/$R/git/refs/heads/$B"
[ "$(at)" != gone ] && try "git push delete" git push -q origin ":refs/heads/$B"
echo "end: $B at $(at)"
