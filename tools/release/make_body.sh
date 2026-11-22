#!/usr/bin/env bash
# Writes the text of the 'latest' release: "Sürüm X · Build: N" (which every
# app version reads), the "what's new" list from release_notes.json and the
# nightly dictionary commits since the published release. Only reads GitHub.
#
#   GH_TOKEN=... GH_REPO=owner/repo tools/release/make_body.sh SRC SHA VERSION BUILD OUT
#
# SRC is a checkout with full history that contains SHA.
set -euo pipefail
src=$1 sha=$2 version=$3 build=$4 out=$5
work=$(mktemp -d)
gh release view latest --json body --jq .body > "$work/prev-body.md" || : > "$work/prev-body.md"
prev=$(gh release view latest --json targetCommitish --jq .targetCommitish || true)
if [ -n "$prev" ] && git -C "$src" cat-file -e "$prev^{commit}" 2>/dev/null; then
  git -C "$src" log --format=%s "$prev..$sha" > "$work/commits.txt"
else
  : > "$work/commits.txt"
fi
python3 -I "$src/tools/release/release_notes.py" --version "$version" --build "$build" \
  --prev-body "$work/prev-body.md" --commits "$work/commits.txt" --notes "$src/release_notes.json" > "$out"
cp "$work/prev-body.md" "$out.previous"
