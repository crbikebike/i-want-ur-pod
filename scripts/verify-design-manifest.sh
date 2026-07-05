#!/usr/bin/env bash
# Verifies that every Swift "Translated from design/kit/..." header comment
# cites a kit file that (a) exists on disk and (b) is registered in
# design/kit/MANIFEST.md. Catches the exact class of drift that produced the
# ResultRow.swift / Discover-first-run mistranslations: a header comment
# claiming a source the file doesn't actually match, with nothing checking it.
#
# Not wired into CI yet (there is none in this repo) — run manually, and wire
# this into CI the moment one exists. See docs/design/direction.md §10 and
# design/kit/MANIFEST.md.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

manifest="design/kit/MANIFEST.md"
if [[ ! -f "$manifest" ]]; then
  echo "error: $manifest not found" >&2
  exit 1
fi

fail=0

# Every "design/kit/....html" path referenced anywhere in a Swift header
# comment, paired with the file it was found in.
while IFS=: read -r swift_file kit_path; do
  [[ -z "$kit_path" ]] && continue

  if [[ ! -f "$kit_path" ]]; then
    echo "FAIL: $swift_file cites '$kit_path', which does not exist on disk"
    fail=1
    continue
  fi

  if ! grep -qF "$kit_path" "$manifest" && ! grep -qF "$(basename "$kit_path")" "$manifest"; then
    echo "FAIL: $swift_file cites '$kit_path', which is not registered in $manifest"
    fail=1
  fi
done < <(
  grep -rEo '^// .*(design/kit/[A-Za-z0-9_./-]+\.html)' \
    --include='*.swift' Packages IWantUrPod 2>/dev/null \
  | sed -E 's#^([^:]+):.*(design/kit/[A-Za-z0-9_./-]+\.html).*#\1:\2#'
)

if [[ "$fail" -eq 0 ]]; then
  echo "OK: every Swift design/kit citation is registered in $manifest"
else
  echo
  echo "See $manifest before adding or fixing a citation." >&2
fi

exit "$fail"
