#!/usr/bin/env bash
set -Eeuo pipefail

artifact_dir=${1:-build/complex-projective-follower}
mkdir -p "$artifact_dir"

assembly=build/exec/polar-complex.arm-thumb.S
selftest=build/exec/backend-selftest
[[ -f $assembly ]] || { echo "missing $assembly" >&2; exit 1; }
[[ -x $selftest ]] || { echo "missing $selftest" >&2; exit 1; }

grep -q '^polar_multiply_magnitude:' "$assembly"
grep -q '^polar_multiply_phase:' "$assembly"
grep -q 'vmul.f32' "$assembly"
grep -q 'vadd.f32' "$assembly"
qemu-arm -cpu cortex-a9 "$selftest"

source_head=${SOURCE_HEAD_SHA:-$(git rev-parse HEAD)}
tested_checkout=$(git rev-parse HEAD)
canonical_semantics_sha=${IDRIC_COMPLEX_SEMANTICS_SHA:-unresolved}
pinned_compiler_sha=081b9cde0591154839fb5d80d76e5570e0436300
assembly_sha=$(sha256sum "$assembly" | awk '{print $1}')
selftest_sha=$(sha256sum "$selftest" | awk '{print $1}')

cat > "$artifact_dir/receipt.tsv" <<EOF
COMPLEX_PROJECTIVE_THUMB_FOLLOWER	1
repository	isomorphisms/idric-arm-thumb
source_head_sha	$source_head
tested_checkout_sha	$tested_checkout
compiler_repository	isomorphisms/Idric
compiler_sha	$pinned_compiler_sha
canonical_complex_projective_semantics_sha	$canonical_semantics_sha
implementation_status	PROVISIONAL_DISPOSABLE
representation	current follower uses polar Float32 leaves; not shared semantics
stage	complex_multiplication_lowering	PASS
stage	thumb2_assembly	PASS
stage	qemu_complex_multiplication_execution	PASS
stage	shared_cartesian_numerical_corpus	SKIP	not implemented by provisional polar slice
stage	projective_equivalence_corpus	SKIP	not implemented by provisional polar slice
stage	headless_render	SKIP	not implemented by provisional polar slice
stage	physical_arm_device	SKIP	QEMU receipt only
polar_assembly_sha256	$assembly_sha
selftest_elf_sha256	$selftest_sha
EOF

cat "$artifact_dir/receipt.tsv"
