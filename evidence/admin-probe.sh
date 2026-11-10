#!/usr/bin/env bash
# Attempts as the repository admin, the bypass actor of version-tag-protection
# and an ordinary actor to tag-protection. Usage: admin-probe.sh <repo-dir> <n>
set -u
cd "$1" || exit 1
N=$2
R=TylerVigario/ruleset-probe
git fetch -q origin
head=$(git rev-parse origin/main)
parent=$(git rev-parse origin/main^)
echo "head=${head:0:7} parent=${parent:0:7}  $(date -u +%FT%TZ)"
try() {
  local label=$1
  shift
  if out=$("$@" 2>&1); then
    echo "ALLOWED  $label"
  else
    echo "REFUSED  $label :: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-400)"
  fi
}
create() { gh api "repos/$R/git/refs" -f ref="refs/tags/$1" -f sha="$2"; }
ff() { gh api -X PATCH "repos/$R/git/refs/tags/$1" -f sha="$2" -F force=false; }
del() { gh api -X DELETE "repos/$R/git/refs/tags/$1"; }

echo "-- creating v tags (admin bypasses version-tag-protection)"
try "git push creates v$N.0.0" git push -q origin "$parent:refs/tags/v$N.0.0"
try "refs API creates v$N.0.1" create "v$N.0.1" "$parent"
try "publishing a release creates v$N.0.2" \
  gh release create "v$N.0.2" -R "$R" --target "$head" --title probe --notes probe
try "draft release v$N.0.3" \
  gh release create "v$N.0.3" -R "$R" --draft --target "$head" --title probe --notes probe
try "publishing draft v$N.0.3 creates its tag" gh release edit "v$N.0.3" -R "$R" --draft=false

echo "-- moving and deleting them (tag-protection, no bypass for anyone)"
try "git push fast-forwards v$N.0.0" git push -q origin "$head:refs/tags/v$N.0.0"
try "git push forces v$N.0.0" git push -q --force origin "$head:refs/tags/v$N.0.0"
try "refs API fast-forwards v$N.0.1" ff "v$N.0.1" "$head"
try "git push deletes v$N.0.1" git push -q origin ":refs/tags/v$N.0.1"
try "refs API deletes v$N.0.1" del "v$N.0.1"

echo "-- an ordinary tag"
try "git push creates q$N" git push -q origin "$parent:refs/tags/q$N"
try "git push fast-forwards q$N" git push -q origin "$head:refs/tags/q$N"

echo
echo "tags now:"
gh api "repos/$R/git/refs/tags" --jq '.[] | "\(.ref) \(.object.sha[0:7])"'
echo "releases now:"
gh api "repos/$R/releases" --jq '.[] | "\(.tag_name) draft=\(.draft) immutable=\(.immutable) author=\(.author.login)"'
