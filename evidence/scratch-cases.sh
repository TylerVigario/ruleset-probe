#!/usr/bin/env bash
# Synthetic release commits on the scratch repository, each GitHub-constructed
# (createCommitOnBranch, as publish does) except the unsigned case, then the
# branch's Decide run against each. Usage: scratch-cases.sh <scratch-clone>
set -u
F=$(cd "$(dirname "$0")" && pwd)
C=$1
R=TylerVigario/ruleset-probe
cd "$C" || exit 1
git fetch -q origin
base=$(git rev-parse origin/main)
echo "base=${base:0:7}  $(date -u +%FT%TZ)"
work=$(mktemp -d)

# make <version> <lock-root-version> <variant> -> files in $work/<version>/
make() {
  local v=$1 lockroot=$2 variant=$3 d="$work/$1"
  mkdir -p "$d"
  git show "$base:package.json" | jq --arg v "$v" '.version = $v' > "$d/package.json"
  git show "$base:package-lock.json" | jq --arg v "$v" --arg r "$lockroot" \
    '.version = $v | .packages[""].version = $r' > "$d/package-lock.json"
  { git show "$base:CHANGELOG.md"; printf '\n## v%s\n' "$v"; } > "$d/CHANGELOG.md"
  case $variant in
    scripts) jq '.scripts = {"postinstall": "echo hi"}' "$d/package.json" > "$d/p" && mv "$d/p" "$d/package.json" ;;
    lockdep) jq '.packages["node_modules/x"] = {"version": "1.0.0"}' "$d/package-lock.json" > "$d/p" && mv "$d/p" "$d/package-lock.json" ;;
  esac
}
# commit <version> [extra-file] -> prints the new commit's oid
commit() {
  local v=$1 extra=${2:-} d="$work/$1" branch="case/v$1"
  gh api "repos/$R/git/refs" -f ref="refs/heads/$branch" -f sha="$base" >/dev/null
  jq -n --arg repo "$R" --arg head "$base" --arg branch "$branch" --arg msg "chore(release): v$v" \
    --rawfile pkg "$d/package.json" --rawfile lock "$d/package-lock.json" --rawfile log "$d/CHANGELOG.md" \
    --arg extra "$extra" \
    '{query:"mutation($input:CreateCommitOnBranchInput!){createCommitOnBranch(input:$input){commit{oid}}}",
      variables:{input:{branch:{repositoryNameWithOwner:$repo,branchName:$branch},expectedHeadOid:$head,
        message:{headline:$msg},
        fileChanges:{additions:([
          {path:"package.json",contents:($pkg|@base64)},
          {path:"package-lock.json",contents:($lock|@base64)},
          {path:"CHANGELOG.md",contents:($log|@base64)}]
          + (if $extra == "" then [] else [{path:$extra,contents:("extra\n"|@base64)}] end))}}}}' > "$d/mutation.json"
  gh api graphql --input "$d/mutation.json" --jq '.data.createCommitOnBranch.commit.oid'
}
# unsigned <version> -> a commit with the good case's tree, made through the git data API
unsigned() {
  local v=$1 d="$work/$1" blobs tree
  tree=$(jq -n --arg base "$(git rev-parse "$base^{tree}")" \
    --rawfile pkg "$d/package.json" --rawfile lock "$d/package-lock.json" --rawfile log "$d/CHANGELOG.md" \
    '{base_tree:$base, tree:[{path:"package.json",mode:"100644",type:"blob",content:$pkg},
      {path:"package-lock.json",mode:"100644",type:"blob",content:$lock},
      {path:"CHANGELOG.md",mode:"100644",type:"blob",content:$log}]}' \
    | gh api "repos/$R/git/trees" --input - --jq .sha)
  jq -n --arg tree "$tree" --arg parent "$base" --arg msg "chore(release): v$v" \
    '{message:$msg, tree:$tree, parents:[$parent]}' | gh api "repos/$R/git/commits" --input - --jq .sha
}
tag() { gh api "repos/$R/git/refs" -f ref="refs/tags/v$1" -f sha="$2" >/dev/null; }
publish() { gh release create "v$1" -R "$R" --verify-tag --title "v$1" --notes probe >/dev/null; }
draft() { gh release create "v$1" -R "$R" --draft --verify-tag --title "v$1" --notes probe >/dev/null; }

decide() { # <label> <tag> <bot>
  git fetch -q origin "refs/tags/$2:refs/tags/$2"
  git tag --list 'v*' | xargs -r -I{} git update-ref -d "refs/tags/{}" 2>/dev/null
  git fetch -q origin "refs/tags/$2:refs/tags/$2"
  git checkout -q --detach "$base"
  bash "$F/run-case.sh" "$1" "$F/release-branch.yml" "$C" "$R" "$3"
}

N=${N:?set N, a fresh minor for this run}
v() { echo "9.$N.$1"; }

make "$(v 1)" "$(v 1)" none;    o=$(commit "$(v 1)");            tag "$(v 1)" "$o"; publish "$(v 1)"
make "$(v 2)" "$(v 2)" none;    o=$(commit "$(v 2)" EXTRA.md);   tag "$(v 2)" "$o"; publish "$(v 2)"
make "$(v 3)" "$(v 3)" scripts; o=$(commit "$(v 3)");            tag "$(v 3)" "$o"; publish "$(v 3)"
make "$(v 4)" "$(v 4)" lockdep; o=$(commit "$(v 4)");            tag "$(v 4)" "$o"; publish "$(v 4)"
make "$(v 5)" 0.0.0 none;       o=$(commit "$(v 5)");            tag "$(v 5)" "$o"; publish "$(v 5)"
make "$(v 6)" "$(v 6)" none;    o=$(commit "$(v 6)");            tag "$(v 6)" "$o"; draft "$(v 6)"
make "$(v 7)" "$(v 7)" none;    o=$(unsigned "$(v 7)");          tag "$(v 7)" "$o"; publish "$(v 7)"

decide "S1 good: a constructed commit changing only the version and changelog" "v$(v 1)" TylerVigario
decide "S1' the same, expecting the website's bot as author" "v$(v 1)" 'website-release[bot]'
decide "S2 an extra file changed" "v$(v 2)" TylerVigario
decide "S3 package.json changed beyond its version" "v$(v 3)" TylerVigario
decide "S4 package-lock.json changed beyond its version" "v$(v 4)" TylerVigario
decide "S5 package-lock.json's root package left at the old version" "v$(v 5)" TylerVigario
decide "S6 the release is still a draft" "v$(v 6)" TylerVigario
decide "S7 an unsigned commit through the git data API" "v$(v 7)" TylerVigario
rm -rf "$work"
