#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$repo_root"

out=build/real-haskell
mkdir -p "$out/ghc" "$out/asm-build"

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
  -outputdir "$out/ghc" \
  tests/real-haskell/bench/BranchCorpus.hs \
  -o "$out/branch-corpus"

# Produce one explicit assembly file rather than relying on GHC's temporary-file
# placement. This is evidence for which branch/table/arithmetic form GHC chose.
ghc \
  -O2 \
  -S \
  -fforce-recomp \
  -outputdir "$out/asm-build" \
  tests/real-haskell/bench/BranchCorpus.hs \
  -o "$out/BranchCorpus.s"

"$out/branch-corpus" | tee "$out/haskell.tsv"
