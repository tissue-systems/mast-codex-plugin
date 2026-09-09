#!/usr/bin/env bash
# Copies the scripts each skill runs from scripts/ into that skill's own
# scripts/ directory. Codex resolves a path in SKILL.md against the skill's
# directory, and a skills-only bundle ships nothing outside skills/, so each
# skill carries the scripts it names. scripts/ at the root stays the source;
# the hooks run from there. tests/test.sh fails when the copies drift.
set -eu
cd "$(dirname "${BASH_SOURCE[0]}")/.."
declare -A need=(
  [mast-setup]="lib.sh mast-status.sh mast-send.sh"
  [mast-test]="lib.sh mast-status.sh mast-send.sh"
  [mast-page]="lib.sh mast-send.sh mast-status.sh"
  [mast-ask]="lib.sh mast-ask.sh"
)
for skill in "${!need[@]}"; do
  mkdir -p "skills/$skill/scripts"
  for f in ${need[$skill]}; do cp "scripts/$f" "skills/$skill/scripts/$f"; done
done
echo synced
