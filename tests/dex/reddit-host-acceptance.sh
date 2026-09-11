#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
idric=${IDRIC:-idris2}
runtime_library=${IDRIC_RUNTIME_LIBRARY:-$(dirname -- "$idric")/idris2_app/libidris2_support.so}
build="$repo_root/build/exec"
reddit_build="$build/reddit"
generator="$build/reddit-dex-gen"
candidate="$reddit_build/classes.dex"
first_candidate="$reddit_build/classes-first.dex"
receipt="$reddit_build/host-receipt.txt"
oracle_dir="$repo_root/build/oracles"
baksmali="$oracle_dir/baksmali-3.0.10.jar"
smali="$oracle_dir/smali-3.0.10.jar"
baksmali_sha=37ae4a41a8886e15c20b8362fa4250f96bbdb55e1a608199ad8b5dff068b588f
smali_sha=32fa0e88a6c397b3922201adf5f3e534fbaed5a663c71d0c558c3ddce0af844a

cd "$repo_root"
mkdir -p "$reddit_build" "$oracle_dir"
rm -rf "$reddit_build/baksmali-candidate" "$reddit_build/baksmali-oracle" \
  "$reddit_build/oracle-source"

"$idric" --build reddit-dex.ipkg
IDRIS2_PATH="$repo_root/build/ttc:${IDRIS2_PATH:-}" \
  "$idric" --source-dir "$repo_root/tests/dex" \
  "$repo_root/tests/dex/RedditCliDexGen.idr" -o reddit-dex-gen
cp "$runtime_library" "${generator}_app/"

LD_LIBRARY_PATH="$(dirname -- "$runtime_library"):${LD_LIBRARY_PATH:-}" \
  "$generator"
cp "$candidate" "$first_candidate"
LD_LIBRARY_PATH="$(dirname -- "$runtime_library"):${LD_LIBRARY_PATH:-}" \
  "$generator"
cmp "$first_candidate" "$candidate"

if [ ! -f "$baksmali" ]; then
  curl -fL --retry 3 \
    https://github.com/baksmali/smali/releases/download/3.0.10/baksmali-3.0.10-fat-release.jar \
    -o "$baksmali"
fi
printf '%s  %s\n' "$baksmali_sha" "$baksmali" | sha256sum -c -

if [ ! -f "$smali" ]; then
  curl -fL --retry 3 \
    https://github.com/baksmali/smali/releases/download/3.0.10/smali-3.0.10-fat-release.jar \
    -o "$smali"
fi
printf '%s  %s\n' "$smali_sha" "$smali" | sha256sum -c -

mkdir -p "$reddit_build/baksmali-candidate" "$reddit_build/oracle-source" \
  "$reddit_build/baksmali-oracle"
java -jar "$baksmali" disassemble "$candidate" \
  -o "$reddit_build/baksmali-candidate"
cp "$repo_root/tests/dex/oracles/RedditCli.smali" \
  "$reddit_build/oracle-source/RedditCli.smali"
java -jar "$smali" assemble "$reddit_build/oracle-source" \
  -o "$reddit_build/oracle.dex"
java -jar "$baksmali" disassemble "$reddit_build/oracle.dex" \
  -o "$reddit_build/baksmali-oracle"

candidate_smali="$reddit_build/baksmali-candidate/org/isomorphisms/reddit/RedditCli.smali"
oracle_smali="$reddit_build/baksmali-oracle/org/isomorphisms/reddit/RedditCli.smali"
cmp "$oracle_smali" "$candidate_smali"

{
  echo 'REDDIT_DIRECT_DEX        1'
  echo 'direct encoder          PASS'
  echo 'deterministic output    PASS'
  echo 'smali oracle comparison PASS oracle_only'
  echo 'javac production path   ABSENT'
  echo 'Kotlin production path  ABSENT'
  echo 'Gradle production path  ABSENT'
  echo 'd8 production path      ABSENT'
  echo 'smali production path   ABSENT'
  printf 'classes.dex bytes       %s\n' "$(wc -c < "$candidate")"
  printf 'classes.dex SHA-256     %s\n' "$(sha256sum "$candidate" | cut -d' ' -f1)"
} >"$receipt"

cat "$receipt"
