#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

duplicate_paths=()
while IFS= read -r path; do
  name="$(basename "$path")"
  shopt -s nocasematch
  if [[ "$name" =~ [[:space:]][0-9]+\.swift$ ]] ||
    [[ "$name" =~ [[:space:]]copy([[:space:]][0-9]+)?\.swift$ ]] ||
    [[ "$name" =~ [[:space:]]-\ Copy([[:space:]][0-9]+)?\.swift$ ]]; then
    duplicate_paths+=("$path")
  fi
  shopt -u nocasematch
done < <(find Sources Tests -type f -name '*.swift' -print)

if (( ${#duplicate_paths[@]} > 0 )); then
  echo "Duplicate Swift source copies found:" >&2
  printf '  %s\n' "${duplicate_paths[@]}" >&2
  echo "Remove or rename these files before building; SwiftPM compiles untracked files under Sources and Tests." >&2
  exit 1
fi
