IDRIC ?= idris2
IDRIC_REVISION ?= 081b9cde0
ARM_CLANG ?= clang
ARM_TARGET ?= armv7a-linux-androideabi21
ARM_EXEC_TARGET ?= armv7a-linux-gnueabihf
QEMU_ARM ?= qemu-arm

BACKEND_SOURCES := $(wildcard src/Backend/ARMThumb/*.idr) src/RendererPrimitives.idr backend.ipkg
DRIVER := build/exec/idric-arm-thumb
AFFINE_ASSEMBLY := build/exec/affine.arm-thumb.S
AFFINE_OBJECT := build/exec/affine.arm-thumb.o
OPERATIONS_ASSEMBLY := build/exec/operations.arm-thumb.S
OPERATIONS_OBJECT := build/exec/operations.arm-thumb.o
SELFTEST := build/exec/backend-selftest
INVALID_INT_LOG := build/exec/invalid-int.log
TOO_MANY_ARGS_LOG := build/exec/too-many-args.log
INVALID_RESULT_LOG := build/exec/invalid-result.log
DETERMINISM_A := build/exec/determinism-a.arm-thumb.S
DETERMINISM_B := build/exec/determinism-b.arm-thumb.S

.PHONY: check-compiler check driver examples inspect reject reject-invalid-int \
	reject-too-many-args reject-invalid-result assemble abi semantic determinism \
	branching-spec-test source-test lowering-test assembly-test semantic-test \
	determinism-test test verify clean

check-compiler:
	@$(IDRIC) --version | grep -q '$(IDRIC_REVISION)' || { \
		echo "Expected Idriç compiler revision $(IDRIC_REVISION)"; \
		$(IDRIC) --version; \
		exit 1; \
	}

check: check-compiler
	$(IDRIC) --typecheck backend.ipkg

driver: $(DRIVER)

$(DRIVER): $(BACKEND_SOURCES)
	$(IDRIC) --build backend.ipkg

$(AFFINE_ASSEMBLY): $(DRIVER) examples/Affine.idric
	IDRIS2_PATH="$(CURDIR)/build/ttc:$${IDRIS2_PATH}" \
		./$(DRIVER) --cg arm-thumb --source-dir examples examples/Affine.idric -o affine

$(OPERATIONS_ASSEMBLY): $(DRIVER) examples/Operations.idric
	IDRIS2_PATH="$(CURDIR)/build/ttc:$${IDRIS2_PATH}" \
		./$(DRIVER) --cg arm-thumb --source-dir examples examples/Operations.idric -o operations

examples: $(AFFINE_ASSEMBLY) $(OPERATIONS_ASSEMBLY)

inspect: examples
	grep -q '^evaluate_affine:' $(AFFINE_ASSEMBLY)
	grep -q 'vmul.f32' $(AFFINE_ASSEMBLY)
	grep -q 'vadd.f32' $(AFFINE_ASSEMBLY)
	grep -q '^\.arch armv7-a' $(AFFINE_ASSEMBLY)
	grep -q '^\.thumb' $(AFFINE_ASSEMBLY)
	grep -q '^\.fpu vfpv3-d16' $(AFFINE_ASSEMBLY)
	grep -q '^float32_sub_test:' $(OPERATIONS_ASSEMBLY)
	grep -q '^float32_div_test:' $(OPERATIONS_ASSEMBLY)
	grep -q '^float32_neg_test:' $(OPERATIONS_ASSEMBLY)
	grep -q '^float32_abs_test:' $(OPERATIONS_ASSEMBLY)
	grep -q '^float32_sqrt_test:' $(OPERATIONS_ASSEMBLY)
	grep -q '^float32_load_test:' $(OPERATIONS_ASSEMBLY)
	grep -q '^float32_load_second:' $(OPERATIONS_ASSEMBLY)
	grep -q '^float32_identity:' $(OPERATIONS_ASSEMBLY)
	grep -q '^float32_first:' $(OPERATIONS_ASSEMBLY)
	grep -q '^float32_fourth:' $(OPERATIONS_ASSEMBLY)
	grep -q '^float32_sum_four:' $(OPERATIONS_ASSEMBLY)
	grep -q 'vsub.f32' $(OPERATIONS_ASSEMBLY)
	grep -q 'vdiv.f32' $(OPERATIONS_ASSEMBLY)
	grep -q 'vneg.f32' $(OPERATIONS_ASSEMBLY)
	grep -q 'vabs.f32' $(OPERATIONS_ASSEMBLY)
	grep -q 'vsqrt.f32' $(OPERATIONS_ASSEMBLY)
	grep -Eq 'add\.w[[:space:]]+r0, r0, r1, lsl #2' $(OPERATIONS_ASSEMBLY)
	grep -q 'movw' $(OPERATIONS_ASSEMBLY)

reject-invalid-int: $(DRIVER) tests/source/InvalidInt.idric
	@set -e; \
	if IDRIS2_PATH="$(CURDIR)/build/ttc:$${IDRIS2_PATH}" \
		./$(DRIVER) --cg arm-thumb --source-dir tests/source \
		tests/source/InvalidInt.idric -o invalid_int > $(INVALID_INT_LOG) 2>&1; then \
		cat $(INVALID_INT_LOG); \
		echo 'Expected 64-bit Int source ABI to be rejected'; \
		exit 1; \
	fi
	grep -q 'arm-thumb rejected source ABI' $(INVALID_INT_LOG)
	grep -q 'unsupported source primitive type' $(INVALID_INT_LOG)

reject-too-many-args: $(DRIVER) tests/source/TooManyArgs.idric
	@set -e; \
	if IDRIS2_PATH="$(CURDIR)/build/ttc:$${IDRIS2_PATH}" \
		./$(DRIVER) --cg arm-thumb --source-dir tests/source \
		tests/source/TooManyArgs.idric -o too_many_args > $(TOO_MANY_ARGS_LOG) 2>&1; then \
		cat $(TOO_MANY_ARGS_LOG); \
		echo 'Expected five-word source ABI to be rejected'; \
		exit 1; \
	fi
	grep -q 'arm-thumb rejected source ABI' $(TOO_MANY_ARGS_LOG)
	grep -q 'more than four one-word arguments' $(TOO_MANY_ARGS_LOG)

reject-invalid-result: $(DRIVER) tests/source/InvalidResult.idric
	@set -e; \
	if IDRIS2_PATH="$(CURDIR)/build/ttc:$${IDRIS2_PATH}" \
		./$(DRIVER) --cg arm-thumb --source-dir tests/source \
		tests/source/InvalidResult.idric -o invalid_result > $(INVALID_RESULT_LOG) 2>&1; then \
		cat $(INVALID_RESULT_LOG); \
		echo 'Expected non-Float32 result ABI to be rejected'; \
		exit 1; \
	fi
	grep -q 'arm-thumb rejected source ABI' $(INVALID_RESULT_LOG)
	grep -q 'result must be RendererPrimitives.Float32' $(INVALID_RESULT_LOG)

reject: reject-invalid-int reject-too-many-args reject-invalid-result

$(AFFINE_OBJECT): $(AFFINE_ASSEMBLY)
	$(ARM_CLANG) --target=$(ARM_TARGET) -c -fPIC -march=armv7-a -mthumb \
		-mfpu=vfpv3-d16 -mfloat-abi=softfp $(AFFINE_ASSEMBLY) -o $(AFFINE_OBJECT)

$(OPERATIONS_OBJECT): $(OPERATIONS_ASSEMBLY)
	$(ARM_CLANG) --target=$(ARM_TARGET) -c -fPIC -march=armv7-a -mthumb \
		-mfpu=vfpv3-d16 -mfloat-abi=softfp $(OPERATIONS_ASSEMBLY) -o $(OPERATIONS_OBJECT)

assemble: $(AFFINE_OBJECT) $(OPERATIONS_OBJECT)

abi: assemble
	file $(AFFINE_OBJECT) | grep -q 'ELF 32-bit.*ARM'
	file $(OPERATIONS_OBJECT) | grep -q 'ELF 32-bit.*ARM'
	readelf -h $(AFFINE_OBJECT) | grep -q 'Class:.*ELF32'
	readelf -h $(AFFINE_OBJECT) | grep -q 'Machine:.*ARM'
	readelf -A $(AFFINE_OBJECT) | grep -q 'Tag_THUMB_ISA_use: Thumb-2'
	readelf -A $(AFFINE_OBJECT) | grep -q 'Tag_FP_arch: VFPv3-D16'
	readelf -sW $(AFFINE_OBJECT) | grep -q 'evaluate_affine'
	readelf -sW $(OPERATIONS_OBJECT) | grep -q 'float32_load_test'
	readelf -sW $(OPERATIONS_OBJECT) | grep -q 'float32_fourth'
	readelf -sW $(OPERATIONS_OBJECT) | grep -q 'float32_sum_four'
	@test -z "$$(nm -u $(AFFINE_OBJECT))"
	@test -z "$$(nm -u $(OPERATIONS_OBJECT))"

$(SELFTEST): $(AFFINE_ASSEMBLY) $(OPERATIONS_ASSEMBLY) tests/arm/backend_selftest.S
	$(ARM_CLANG) --target=$(ARM_EXEC_TARGET) -fuse-ld=lld -nostdlib -static \
		-march=armv7-a -mthumb -mfpu=vfpv3-d16 -mfloat-abi=softfp \
		-Wl,-e,_start -Wl,--no-dynamic-linker \
		$(AFFINE_ASSEMBLY) $(OPERATIONS_ASSEMBLY) tests/arm/backend_selftest.S \
		-o $(SELFTEST)

semantic: $(SELFTEST)
	file $(SELFTEST) | grep -q 'ELF 32-bit.*ARM'
	$(QEMU_ARM) -cpu cortex-a9 $(SELFTEST)

$(DETERMINISM_A): $(DRIVER) examples/Operations.idric
	IDRIS2_PATH="$(CURDIR)/build/ttc:$${IDRIS2_PATH}" \
		./$(DRIVER) --cg arm-thumb --source-dir examples examples/Operations.idric -o determinism-a

$(DETERMINISM_B): $(DRIVER) examples/Operations.idric
	IDRIS2_PATH="$(CURDIR)/build/ttc:$${IDRIS2_PATH}" \
		./$(DRIVER) --cg arm-thumb --source-dir examples examples/Operations.idric -o determinism-b

determinism: $(DETERMINISM_A) $(DETERMINISM_B)
	@cmp -s $(DETERMINISM_A) $(DETERMINISM_B) || { \
		diff -u $(DETERMINISM_A) $(DETERMINISM_B); \
		echo 'ARM Thumb assembly changed across identical compilations'; \
		exit 1; \
	}

branching-spec-test: check-compiler driver
	IDRIC="$(IDRIC)" bash tests/branching/check-current-boundary.sh

source-test: check reject
lowering-test: inspect
assembly-test: abi
semantic-test: semantic
determinism-test: determinism

test: source-test lowering-test assembly-test semantic-test determinism-test branching-spec-test

verify: test

clean:
	rm -rf build
