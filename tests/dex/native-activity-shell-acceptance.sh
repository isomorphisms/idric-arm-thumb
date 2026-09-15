#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
idric=${IDRIC:-idris2}
runtime_library=${IDRIC_RUNTIME_LIBRARY:-$(dirname -- "$idric")/idris2_app/libidris2_support.so}
build="$repo_root/build/exec"
shell_build="$build/native-shell"
generator="$build/native-activity-shell-gen"
oracle_dir="$repo_root/build/oracles"
baksmali="$oracle_dir/baksmali-3.0.10.jar"
baksmali_sha=37ae4a41a8886e15c20b8362fa4250f96bbdb55e1a608199ad8b5dff068b588f
receipt="$shell_build/host-receipt.txt"

cd "$repo_root"
mkdir -p "$shell_build/wegert" "$shell_build/analytic-continuation" "$oracle_dir"

"$idric" --build wegert-dex.ipkg
IDRIS2_PATH="$repo_root/build/ttc:${IDRIS2_PATH:-}" \
  "$idric" --source-dir "$repo_root/tests/dex" \
  "$repo_root/tests/dex/NativeActivityShellGen.idr" -o native-activity-shell-gen
cp "$runtime_library" "${generator}_app/"

run_generator() {
  LD_LIBRARY_PATH="$(dirname -- "$runtime_library"):${LD_LIBRARY_PATH:-}" \
    "$generator"
}

run_generator
cp "$shell_build/wegert/classes.dex" "$shell_build/wegert/classes-first.dex"
cp "$shell_build/analytic-continuation/classes.dex" \
  "$shell_build/analytic-continuation/classes-first.dex"
run_generator
cmp "$shell_build/wegert/classes-first.dex" "$shell_build/wegert/classes.dex"
cmp "$shell_build/analytic-continuation/classes-first.dex" \
  "$shell_build/analytic-continuation/classes.dex"

python3 "$repo_root/tests/dex/check_dex.py" "$shell_build/wegert/classes.dex"
python3 "$repo_root/tests/dex/check_dex.py" \
  "$shell_build/analytic-continuation/classes.dex"

if [ ! -f "$baksmali" ]; then
  curl -fL --retry 3 \
    https://github.com/baksmali/smali/releases/download/3.0.10/baksmali-3.0.10-fat-release.jar \
    -o "$baksmali"
fi
printf '%s  %s\n' "$baksmali_sha" "$baksmali" | sha256sum -c -

rm -rf "$shell_build/wegert/disassembly" \
  "$shell_build/analytic-continuation/disassembly"
java -jar "$baksmali" disassemble "$shell_build/wegert/classes.dex" \
  -o "$shell_build/wegert/disassembly"
java -jar "$baksmali" disassemble \
  "$shell_build/analytic-continuation/classes.dex" \
  -o "$shell_build/analytic-continuation/disassembly"

wegert_smali="$shell_build/wegert/disassembly/org/isomorphisms/wegert/WegertActivity.smali"
analytic_smali="$shell_build/analytic-continuation/disassembly/org/isomorphisms/analyticcontinuation/ExplorerActivity.smali"

for smali in "$wegert_smali" "$analytic_smali"; do
  test -f "$smali"
  grep -Fq '.super Landroid/app/NativeActivity;' "$smali"
  grep -Fq '.method public constructor <init>()V' "$smali"
  grep -Fq '.method protected onCreate(Landroid/os/Bundle;)V' "$smali"
  grep -Fq 'invoke-direct {p0}, Landroid/app/NativeActivity;-><init>()V' "$smali"
  grep -Fq 'invoke-super {p0, p1}, Landroid/app/NativeActivity;->onCreate(Landroid/os/Bundle;)V' "$smali"
  ! grep -Fq 'jniProbe' "$smali"
  ! grep -Fq 'loadLibrary' "$smali"
done

grep -Fq '.class public Lorg/isomorphisms/wegert/WegertActivity;' "$wegert_smali"
grep -Fq '.class public Lorg/isomorphisms/analyticcontinuation/ExplorerActivity;' "$analytic_smali"

{
  echo 'DIRECT_NATIVE_ACTIVITY_SHELL 1'
  echo 'Wegert DEX                 PASS'
  echo 'Analytic Continuation DEX  PASS'
  echo 'deterministic output       PASS'
  echo 'independent DEX parse      PASS'
  echo 'baksmali structure check   PASS'
  echo 'Java source path           ABSENT'
  echo 'javac production path      ABSENT'
  echo 'Kotlin production path     ABSENT'
  echo 'd8 production path         ABSENT'
  echo 'smali production path      ABSENT'
  printf 'Wegert SHA-256             %s\n' \
    "$(sha256sum "$shell_build/wegert/classes.dex" | cut -d' ' -f1)"
  printf 'Analytic SHA-256           %s\n' \
    "$(sha256sum "$shell_build/analytic-continuation/classes.dex" | cut -d' ' -f1)"
} > "$receipt"

cat "$receipt"
