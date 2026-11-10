#!/usr/bin/env bash
# Run a release.yml's Decide step, exactly as written, in a clone.
# Usage: run-case.sh <label> <release.yml> <clone> <owner/repo> <release-bot>
# The clone's HEAD and tags are the case; set them before calling.
set -u
label=$1 wf=$2 clone=$3 repo=$4 bot=$5
here=$(cd "$(dirname "$0")" && pwd)
script=$(python3 -I "$here/extract-decide.py" "$wf") || exit 2
tmp=$(mktemp -d)
out="$tmp/output"
: > "$out"
(
  cd "$clone" || exit 2
  env -i PATH="$PATH" HOME="$HOME" \
    GH_TOKEN="$(gh auth token)" \
    BUMP=auto GITHUB_OUTPUT="$out" RUNNER_TEMP="$tmp" \
    GITHUB_REPOSITORY="$repo" RELEASE_BOT="$bot" \
    bash -c "$script"
) >"$tmp/log" 2>&1
code=$?
echo "== $label"
echo "   HEAD=$(git -C "$clone" rev-parse --short HEAD)  newest v tag=$(git -C "$clone" tag --list 'v*' --sort=-v:refname | head -n 1)"
echo "   exit=$code"
sed 's/^/   | /' "$tmp/log" | grep -v '^   | $' | cut -c1-260
[ -s "$out" ] && sed 's/^/   > /' "$out"
rm -rf "$tmp"
