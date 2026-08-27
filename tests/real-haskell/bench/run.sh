#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$repo_root"

out=build/real-haskell
mkdir -p "$out/ghc"

{
  printf 'ghc\t%s\n' "$(ghc --numeric-version)"
  printf 'machine\t%s\n' "$(uname -m)"
  printf 'kernel\t%s\n' "$(uname -sr)"
  printf 'BENCH_ITERS\t%s\n' "${BENCH_ITERS:-5000000}"
} > "$out/metadata.tsv"

ghc \
  -O2 \
  -Wall \
  -fforce-recomp \
  -keep-s-files \
  -outputdir "$out/ghc" \
  tests/real-haskell/bench/BranchCorpus.hs \
  -o "$out/branch-corpus"

"$out/branch-corpus" | tee "$out/haskell.tsv"
