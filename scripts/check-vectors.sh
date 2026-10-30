#!/bin/bash
# The equation checker's test vectors are the server's, copied byte for byte
# into RoadSignMathKit/Tests/EquationTests/Resources. This fails when the copy
# differs from the server's contracts/equation-vectors.json on GitHub (or, with
# a folder given, from a checkout of the server repo).
#
#   scripts/check-vectors.sh              compare with the server's main branch
#   scripts/check-vectors.sh <server dir> compare with a checkout
#
# When it fails, copy the server's file over ours and make the tests pass.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
ours="$root/RoadSignMathKit/Tests/EquationTests/Resources/equation-vectors.json"

if [[ $# -gt 0 ]]; then
  theirs=$(cat "$1/contracts/equation-vectors.json")
else
  theirs=$(curl -fsSL https://raw.githubusercontent.com/jthingelstad/roadsignmath.xyz/main/contracts/equation-vectors.json)
fi

if [[ "$theirs" != "$(cat "$ours")" ]]; then
  echo "equation-vectors.json differs from the server's. Copy it over and make the tests pass." >&2
  diff <(printf '%s\n' "$theirs") "$ours" >&2 || true
  exit 1
fi
echo "equation vectors: the same as the server's"
