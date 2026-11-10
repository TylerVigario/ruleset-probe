#!/usr/bin/env bash
# The finish decision against the website's real history and real GitHub data,
# under main's Decide step and the branch's. Local tags only; nothing is pushed.
set -u
F=$(cd "$(dirname "$0")" && pwd)
C=$F/website-clone
R=TylerVigario/website
BOT='website-release[bot]'
cd "$C" || exit 1
real121=$(git rev-parse 'v1.21.1^{commit}')
reset() { # restore the real tags, then apply the case's local changes
  git fetch -q --force origin 'refs/tags/*:refs/tags/*'
  git for-each-ref --format='%(refname)' 'refs/tags/v1.21.2' | xargs -r -n1 git update-ref -d
  git update-ref refs/tags/v1.21.1 "$real121"
}
both() {
  bash "$F/run-case.sh" "$1 — main's Decide" "$F/release-main.yml" "$C" "$R" "$BOT"
  bash "$F/run-case.sh" "$1 — the branch's Decide" "$F/release-branch.yml" "$C" "$R" "$BOT"
}
echo "run at $(date -u +%FT%TZ)"

reset
git checkout -q --detach 'v1.21.1^'
both "W1 genuine: main one behind the real v1.21.1 release commit"

reset
git checkout -q --detach '6cc9dd1^'
git update-ref refs/tags/v1.21.2 6cc9dd1
both "W2 planted: v1.21.2 on a squash merge, no release"

reset
git checkout -q --detach '6cc9dd1^'
git update-ref refs/tags/v1.21.1 6cc9dd1
both "W3 a published release's name on a squash merge"

reset
git checkout -q --detach 'v1.21.0^'
git update-ref refs/tags/v1.21.1 "$(git rev-parse 'v1.21.0^{commit}')"
both "W4 a published release's name on another release's commit"

reset
git checkout -q --detach origin/HEAD 2>/dev/null || git checkout -q --detach main
