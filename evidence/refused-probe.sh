#!/usr/bin/env bash
# Attempts as the repository admin while no ruleset lets anyone bypass.
# Usage: refused-probe.sh <repo-dir> <n>
set -u
cd "$1" || exit 1
N=$2
R=TylerVigario/ruleset-probe
git fetch -q origin
head=$(git rev-parse origin/main)
parent=$(git rev-parse origin/main^)
echo "head=${head:0:7} parent=${parent:0:7}  $(date -u +%FT%TZ)"
echo "rulesets: $(gh api "repos/$R/rulesets" --jq '[.[].id] | map(tostring) | join(",")')"
for id in $(gh api "repos/$R/rulesets" --jq '.[].id'); do
  gh api "repos/$R/rulesets/$id" --jq '"  \(.name): include=\(.conditions.ref_name.include) rules=\([.rules[].type]) bypass=\(.bypass_actors | length)"'
done
try() {
  local label=$1
  shift
  if out=$("$@" 2>&1); then
    echo "ALLOWED  $label"
  else
    echo "REFUSED  $label :: $(printf '%s' "$out" | tr '\n' ' ' | sed -E 's/ +/ /g' | cut -c1-300)"
  fi
}
create() { gh api "repos/$R/git/refs" -f ref="refs/tags/$1" -f sha="$2"; }
ff() { gh api -X PATCH "repos/$R/git/refs/tags/$1" -f sha="$2" -F force=false; }
force() { git push -q --force origin "$2:refs/tags/$1"; }
del() { gh api -X DELETE "repos/$R/git/refs/tags/$1"; }

echo "-- creating v tags"
try "git push creates v$N.0.0" git push -q origin "$parent:refs/tags/v$N.0.0"
try "refs API creates v$N.0.1" create "v$N.0.1" "$parent"
try "publishing a release creates v$N.0.2" \
  gh release create "v$N.0.2" -R "$R" --target "$head" --title probe --notes probe
try "draft release v$N.0.3" \
  gh release create "v$N.0.3" -R "$R" --draft --target "$head" --title probe --notes probe
try "publishing draft v$N.0.3 creates its tag" gh release edit "v$N.0.3" -R "$R" --draft=false
echo "   release v$N.0.2: $(gh api "repos/$R/releases" --jq "[.[] | select(.tag_name==\"v$N.0.2\") | {draft, immutable}]" 2>&1)"
echo "   release v$N.0.3: $(gh api "repos/$R/releases" --jq "[.[] | select(.tag_name==\"v$N.0.3\") | {draft, immutable}]" 2>&1)"

echo "-- an ordinary tag"
try "refs API creates q$N" create "q$N" "$parent"
try "refs API fast-forwards q$N" ff "q$N" "$head"
try "git push forces q$N" force "q$N" "$head"
try "refs API deletes q$N" del "q$N"

echo "-- slashed tags: created at parent, fast-forwarded to head, forced to grandparent, deleted"
grand=$(git rev-parse origin/main~2)
for t in "v$N/nested" "v$N/a/b" "s$N/nested" "s$N/a/b"; do
  try "refs API creates $t" create "$t" "$parent"
  try "refs API fast-forwards $t" ff "$t" "$head"
  try "git push forces $t to grandparent" force "$t" "$grand"
  try "refs API deletes $t" del "$t"
done

echo
echo "tags now:"
gh api "repos/$R/git/refs/tags" --jq '.[] | "\(.ref) \(.object.sha[0:7])"'
echo "releases now:"
gh api "repos/$R/releases" --jq '.[] | "\(.tag_name) draft=\(.draft) immutable=\(.immutable)"'
