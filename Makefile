IDRIC ?= idris2
IDRIC_REVISION ?= 081b9cde0
ARM_CLANG ?= clang
ARM_TARGET ?= armv7a-linux-androideabi21
ARM_EXEC_TARGET ?= armv7a-linux-gnueabihf
QEMU_ARM ?= qemu-arm

BACKEND_SOURCES := $(wildcard src/Backend/ARMThumb/*.idr) \
	$(wildcard src/Backend/DEX/*.idr) src/RendererPrimitives.idr backend.ipkg
DRIVER := build/exec/idric-arm-thumb
IDRIC_RUNTIME_LIBRARY ?= $(dir $(IDRIC))idris2_app/libidris2_support.so
AFFINE_ASSEMBLY := build/exec/affine.arm-thumb.S
AFFINE_OBJECT := build/exec/affine.arm-thumb.o
OPERATIONS_ASSEMBLY := build/exec/operations.arm-thumb.S
OPERATIONS_OBJECT := build/exec/operations.arm-thumb.o
SELFTEST := build/exec/backend-selftest
INVALID_INT_LOG := build/exec/invalid-int.log
TOO_MANY_ARGS_LOG := build/exec/too-many-args.log
INVALID_RESULT_LOG := build/exec/invalid-result.log
INVALID_INT_ARTIFACT := build/exec/invalid_int.arm-thumb.S
TOO_MANY_ARGS_ARTIFACT := build/exec/too_many_args.arm-thumb.S
INVALID_RESULT_ARTIFACT := build/exec/invalid_result.arm-thumb.S
DETERMINISM_A := build/exec/determinism-a.arm-thumb.S
DETERMINISM_B := build/exec/determinism-b.arm-thumb.S
DEX_SOURCE := examples/DexArithmetic.idric
DEX_FILE := build/exec/classes.dex
DEX_CHECKED_ANF := build/exec/classes.checked.anf
DEX_PLAN := build/exec/classes.dex.plan
DEX_SMALI := build/exec/classes.smali
DEX_REPEAT_FILE := build/exec/classes-repeat.dex
DEX_SELFTEST := build/exec/dex-encoder-selftest
DEX_INVALID_LOG := build/exec/invalid-dex-int.log
DEX_INVALID_ARTIFACT := build/exec/invalid-dex-int.dex
DEX_HEADER_CHECK := tests/dex/check_dex.py
DEX_ORACLE_DIR := build/oracles
BAKSMALI_JAR := $(DEX_ORACLE_DIR)/baksmali-3.0.10.jar
SMALI_JAR := $(DEX_ORACLE_DIR)/smali-3.0.10.jar
BAKSMALI_SHA256 := 37ae4a41a8886e15c20b8362fa4250f96bbdb55e1a608199ad8b5dff068b588f
SMALI_SHA256 := 32fa0e88a6c397b3922201adf5f3e534fbaed5a663c71d0c558c3ddce0af844a
DEX_CANDIDATE_DISASSEMBLY := build/exec/baksmali-candidate/Idric/Generated.smali
DEX_ORACLE_FILE := build/exec/oracle-classes.dex
DEX_ORACLE_DISASSEMBLY := build/exec/baksmali-oracle/Idric/Generated.smali
DEX_MALFORMED_FILE := build/exec/malformed-magic.dex
DEX_VALIDATION_RECEIPT := build/exec/dex-validation-receipt.txt

.PHONY: check-compiler check driver examples inspect reject reject-invalid-int \
	reject-too-many-args reject-invalid-result assemble abi semantic determinism \
	branching-spec-test source-test lowering-test assembly-test semantic-test \
	determinism-test dex-fixture dex-encoder-selftest dex-determinism \
	dex-reject dex-header-validation dex-parser-validation dex-oracle-validation \
	dex-malformed-test dex-test dex-device test verify clean

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
	@test -f "$(IDRIC_RUNTIME_LIBRARY)" || { \
		echo "Missing Idriç host runtime library $(IDRIC_RUNTIME_LIBRARY)"; \
		exit 1; \
	}
	cp "$(IDRIC_RUNTIME_LIBRARY)" build/exec/idric-arm-thumb_app/

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
	test ! -e $(INVALID_INT_ARTIFACT) || { \
		echo 'Remove stale $(INVALID_INT_ARTIFACT) before rejection test'; \
		exit 1; \
	}; \
	IDRIS2_PATH="$(CURDIR)/build/ttc:$${IDRIS2_PATH}" \
		./$(DRIVER) --cg arm-thumb --source-dir tests/source \
		tests/source/InvalidInt.idric -o invalid_int > $(INVALID_INT_LOG) 2>&1 || true
	grep -q 'arm-thumb rejected source ABI' $(INVALID_INT_LOG)
	grep -q 'unsupported source primitive type' $(INVALID_INT_LOG)
	test ! -e $(INVALID_INT_ARTIFACT)

reject-too-many-args: $(DRIVER) tests/source/TooManyArgs.idric
	@set -e; \
	test ! -e $(TOO_MANY_ARGS_ARTIFACT) || { \
		echo 'Remove stale $(TOO_MANY_ARGS_ARTIFACT) before rejection test'; \
		exit 1; \
	}; \
	IDRIS2_PATH="$(CURDIR)/build/ttc:$${IDRIS2_PATH}" \
		./$(DRIVER) --cg arm-thumb --source-dir tests/source \
		tests/source/TooManyArgs.idric -o too_many_args > $(TOO_MANY_ARGS_LOG) 2>&1 || true
	grep -q 'arm-thumb rejected source ABI' $(TOO_MANY_ARGS_LOG)
	grep -q 'more than four one-word arguments' $(TOO_MANY_ARGS_LOG)
	test ! -e $(TOO_MANY_ARGS_ARTIFACT)

reject-invalid-result: $(DRIVER) tests/source/InvalidResult.idric
	@set -e; \
	test ! -e $(INVALID_RESULT_ARTIFACT) || { \
		echo 'Remove stale $(INVALID_RESULT_ARTIFACT) before rejection test'; \
		exit 1; \
	}; \
	IDRIS2_PATH="$(CURDIR)/build/ttc:$${IDRIS2_PATH}" \
		./$(DRIVER) --cg arm-thumb --source-dir tests/source \
		tests/source/InvalidResult.idric -o invalid_result > $(INVALID_RESULT_LOG) 2>&1 || true
	grep -q 'arm-thumb rejected source ABI' $(INVALID_RESULT_LOG)
	grep -q 'result must be RendererPrimitives.Float32' $(INVALID_RESULT_LOG)
	test ! -e $(INVALID_RESULT_ARTIFACT)

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

$(DEX_FILE) $(DEX_CHECKED_ANF) $(DEX_PLAN) $(DEX_SMALI) &: $(DRIVER) $(DEX_SOURCE)
	IDRIS2_PATH="$(CURDIR)/build/ttc:$${IDRIS2_PATH}" \
		./$(DRIVER) --cg dex --source-dir examples $(DEX_SOURCE) -o classes

dex-fixture: $(DEX_FILE) $(DEX_CHECKED_ANF) $(DEX_PLAN) $(DEX_SMALI)
	grep -q '^export DexArithmetic.add as add$$' $(DEX_CHECKED_ANF)
	grep -q 'Prelude.EqOrd.<' $(DEX_CHECKED_ANF)
	grep -q '^method add$$' $(DEX_PLAN)
	grep -q 'add-int' $(DEX_PLAN)
	grep -q 'sub-int' $(DEX_PLAN)
	grep -q 'mul-int' $(DEX_PLAN)
	grep -q 'if-lt' $(DEX_PLAN)
	grep -q 'if-eq' $(DEX_PLAN)
	grep -q 'goto' $(DEX_PLAN)
	grep -q 'const v0, -2147483648' $(DEX_PLAN)
	grep -q 'const v0, 2147483647' $(DEX_PLAN)

$(DEX_SELFTEST): $(DRIVER) tests/dex/EncoderSelfTest.idr
	IDRIS2_PATH="$(CURDIR)/build/ttc:$${IDRIS2_PATH}" \
		$(IDRIC) --source-dir tests/dex tests/dex/EncoderSelfTest.idr \
		-o dex-encoder-selftest
	cp "$(IDRIC_RUNTIME_LIBRARY)" build/exec/dex-encoder-selftest_app/

dex-encoder-selftest: $(DEX_SELFTEST)
	LD_LIBRARY_PATH="$(dir $(IDRIC_RUNTIME_LIBRARY)):$${LD_LIBRARY_PATH}" \
		./$(DEX_SELFTEST)

$(DEX_REPEAT_FILE): $(DRIVER) $(DEX_SOURCE)
	IDRIS2_PATH="$(CURDIR)/build/ttc:$${IDRIS2_PATH}" \
		./$(DRIVER) --cg dex --source-dir examples $(DEX_SOURCE) -o classes-repeat

dex-determinism: $(DEX_FILE) $(DEX_REPEAT_FILE)
	cmp $(DEX_FILE) $(DEX_REPEAT_FILE)

dex-reject: $(DRIVER) tests/source/InvalidDexInt.idric
	@set -e; \
	test ! -e $(DEX_INVALID_ARTIFACT) || { \
		echo 'Remove stale $(DEX_INVALID_ARTIFACT) before rejection test'; \
		exit 1; \
	}; \
	IDRIS2_PATH="$(CURDIR)/build/ttc:$${IDRIS2_PATH}" \
		./$(DRIVER) --cg dex --source-dir tests/source \
		tests/source/InvalidDexInt.idric -o invalid-dex-int \
		>$(DEX_INVALID_LOG) 2>&1 || true
	grep -q 'dex rejected source ABI' $(DEX_INVALID_LOG)
	grep -q 'Int32' $(DEX_INVALID_LOG)
	test ! -e $(DEX_INVALID_ARTIFACT)

dex-header-validation: $(DEX_FILE) $(DEX_HEADER_CHECK)
	python3 $(DEX_HEADER_CHECK) $(DEX_FILE)

$(BAKSMALI_JAR):
	mkdir -p $(DEX_ORACLE_DIR)
	curl -fL --retry 3 \
		https://github.com/baksmali/smali/releases/download/3.0.10/baksmali-3.0.10-fat-release.jar \
		-o $@
	echo '$(BAKSMALI_SHA256)  $@' | sha256sum -c -

$(SMALI_JAR):
	mkdir -p $(DEX_ORACLE_DIR)
	curl -fL --retry 3 \
		https://github.com/baksmali/smali/releases/download/3.0.10/smali-3.0.10-fat-release.jar \
		-o $@
	echo '$(SMALI_SHA256)  $@' | sha256sum -c -

$(DEX_CANDIDATE_DISASSEMBLY): $(DEX_FILE) $(BAKSMALI_JAR)
	mkdir -p build/exec/baksmali-candidate
	java -jar $(BAKSMALI_JAR) disassemble $(DEX_FILE) \
		-o build/exec/baksmali-candidate

dex-parser-validation: dex-header-validation $(DEX_CANDIDATE_DISASSEMBLY)
	grep -q '^\.method public static add(II)I$$' $(DEX_CANDIDATE_DISASSEMBLY)
	grep -q 'add-int v0, p0, p1' $(DEX_CANDIDATE_DISASSEMBLY)
	grep -q 'sub-int v0, p0, p1' $(DEX_CANDIDATE_DISASSEMBLY)
	grep -q 'mul-int v0, p0, p1' $(DEX_CANDIDATE_DISASSEMBLY)
	grep -q 'if-lt p0, p1' $(DEX_CANDIDATE_DISASSEMBLY)
	grep -q 'move v0, p0' $(DEX_CANDIDATE_DISASSEMBLY)
	grep -q 'const/4 v0, -0x8' $(DEX_CANDIDATE_DISASSEMBLY)
	grep -q 'const/4 v0, 0x7' $(DEX_CANDIDATE_DISASSEMBLY)
	grep -q 'const/16 v0, -0x8000' $(DEX_CANDIDATE_DISASSEMBLY)
	grep -q 'const/16 v0, 0x7fff' $(DEX_CANDIDATE_DISASSEMBLY)
	grep -q 'const v0, -0x8001' $(DEX_CANDIDATE_DISASSEMBLY)
	grep -q 'const v0, 0x8000' $(DEX_CANDIDATE_DISASSEMBLY)
	grep -q 'const v0, -0x80000000' $(DEX_CANDIDATE_DISASSEMBLY)
	grep -q 'const v0, 0x7fffffff' $(DEX_CANDIDATE_DISASSEMBLY)

$(DEX_ORACLE_FILE): $(DEX_SMALI) $(SMALI_JAR)
	mkdir -p build/exec/smali-oracle-source
	cp $(DEX_SMALI) build/exec/smali-oracle-source/Generated.smali
	java -jar $(SMALI_JAR) assemble build/exec/smali-oracle-source -o $@

$(DEX_ORACLE_DISASSEMBLY): $(DEX_ORACLE_FILE) $(BAKSMALI_JAR)
	mkdir -p build/exec/baksmali-oracle
	java -jar $(BAKSMALI_JAR) disassemble $(DEX_ORACLE_FILE) \
		-o build/exec/baksmali-oracle

dex-oracle-validation: $(DEX_CANDIDATE_DISASSEMBLY) $(DEX_ORACLE_DISASSEMBLY)
	cmp $(DEX_CANDIDATE_DISASSEMBLY) $(DEX_ORACLE_DISASSEMBLY)

$(DEX_MALFORMED_FILE): $(DEX_FILE)
	cp $(DEX_FILE) $@
	printf '\000' | dd of=$@ bs=1 seek=0 count=1 conv=notrunc status=none

dex-malformed-test: $(DEX_MALFORMED_FILE) $(BAKSMALI_JAR)
	@if python3 $(DEX_HEADER_CHECK) $(DEX_MALFORMED_FILE) >/dev/null 2>&1; then \
		echo 'Independent header validator accepted malformed DEX'; \
		exit 1; \
	fi
	@if java -jar $(BAKSMALI_JAR) disassemble $(DEX_MALFORMED_FILE) \
		-o build/exec/baksmali-malformed >/dev/null 2>&1; then \
		echo 'baksmali accepted malformed DEX magic'; \
		exit 1; \
	fi

dex-test: check dex-fixture dex-encoder-selftest dex-determinism dex-reject \
	dex-parser-validation dex-oracle-validation dex-malformed-test
	@{ \
		echo 'source checked        PASS'; \
		echo 'checked ANF retained  PASS'; \
		echo 'DEX generated         PASS'; \
		echo 'DEX parser validation PASS'; \
		echo 'oracle comparison     PASS'; \
		echo 'deterministic output  PASS'; \
		echo 'ART loaded             NOT_VERIFIED'; \
		echo 'ART executed           NOT_VERIFIED'; \
		echo 'result checked         NOT_VERIFIED'; \
		printf 'compiler revision      '; $(IDRIC) --version | head -n 1; \
		printf 'backend revision       '; git rev-parse HEAD; \
		printf 'classes.dex SHA-256    '; sha256sum $(DEX_FILE) | cut -d' ' -f1; \
		echo 'checked form           $(DEX_CHECKED_ANF)'; \
		echo 'DEX plan               $(DEX_PLAN)'; \
	} >$(DEX_VALIDATION_RECEIPT)
	@cat $(DEX_VALIDATION_RECEIPT)

dex-device: dex-test $(SMALI_JAR)
	SMALI_JAR="$(CURDIR)/$(SMALI_JAR)" tests/dex/device-acceptance.sh $(DEX_FILE)

source-test: check reject
lowering-test: inspect
assembly-test: abi
semantic-test: semantic
determinism-test: determinism

test: source-test lowering-test assembly-test semantic-test determinism-test branching-spec-test

verify: test

clean:
	rm -rf build
