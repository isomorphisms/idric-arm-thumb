#!/usr/bin/env bash
# Keep both emulator checks in one process: android-emulator-runner executes
# multiline script entries one line at a time. This is emulator sanity only;
# physical-device acceptance remains in the separate phone wrappers.
set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
workspace=${GITHUB_WORKSPACE:-$repo_root}
cd "$repo_root"

DEX_PROVENANCE_REQUIRED=1 \
  DEX_DEVICE_RECEIPT=build/exec/dex-emulator-receipt.txt \
  SMALI_JAR="$workspace/build/oracles/smali-3.0.10.jar" \
  sh tests/dex/device-acceptance.sh build/exec/classes.dex

WEGERT_ART_RECEIPT=build/exec/wegert/emulator-receipt.txt \
  bash tests/dex/wegert/art-acceptance.sh build/exec/wegert/wegert-test.apk
