IDRIC ?= idris2
IDRIC_REPO ?= $(CURDIR)/Idric
IDRIC_COMPILER_REF ?= Idriç

BACKEND_SOURCES := $(wildcard src/Backend/DEX/*.idr) backend.ipkg
DRIVER := build/exec/idric-dex
IDRIC_RUNTIME_LIBRARY ?= $(dir $(IDRIC))idris2_app/libidris2_support.so
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

.PHONY: branch-separation check-compiler check driver dex-fixture dex-encoder-selftest \
	dex-determinism dex-reject dex-header-validation dex-parser-validation \
	dex-oracle-validation dex-malformed-test dex-test dex-device test verify clean

branch-separation:
	tests/dex/branch-separation.sh

check-compiler:
	@$(IDRIC) --version
	@git -C "$(IDRIC_REPO)" rev-parse --verify HEAD >/dev/null

check: check-compiler
	$(IDRIC) --typecheck backend.ipkg

driver: $(DRIVER)

$(DRIVER): $(BACKEND_SOURCES)
	$(IDRIC) --build backend.ipkg
	@test -f "$(IDRIC_RUNTIME_LIBRARY)" || { \
		echo "Missing Idriç host runtime library $(IDRIC_RUNTIME_LIBRARY)"; \
		exit 1; \
	}
	cp "$(IDRIC_RUNTIME_LIBRARY)" build/exec/idric-dex_app/

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

dex-test: branch-separation check dex-fixture dex-encoder-selftest dex-determinism dex-reject \
	dex-parser-validation dex-oracle-validation dex-malformed-test
	@{ \
		echo 'source checked        PASS'; \
		echo 'checked ANF retained  PASS'; \
		echo 'DEX generated         PASS'; \
		echo 'DEX parser validation PASS'; \
		echo 'oracle comparison     PASS'; \
		echo 'deterministic output  PASS'; \
		echo 'ART loaded             SKIP prerequisite=device_or_emulator'; \
		echo 'ART executed           SKIP prerequisite=ART_loaded'; \
		echo 'result checked         SKIP prerequisite=ART_executed'; \
		echo 'compiler requested ref $(IDRIC_COMPILER_REF)'; \
		printf 'compiler resolved SHA  '; git -C "$(IDRIC_REPO)" rev-parse HEAD; \
		printf 'compiler dirty state   '; if git -C "$(IDRIC_REPO)" status --porcelain | grep -q .; then echo dirty; else echo clean; fi; \
		printf 'compiler revision      '; $(IDRIC) --version | head -n 1; \
		printf 'backend requested ref  %s\n' "$${GITHUB_HEAD_REF:-$${GITHUB_REF_NAME:-local}}"; \
		printf 'backend revision       '; git rev-parse HEAD; \
		printf 'backend dirty state    '; if git status --porcelain | grep -q .; then echo dirty; else echo clean; fi; \
		printf 'classes.dex SHA-256    '; sha256sum $(DEX_FILE) | cut -d' ' -f1; \
		echo 'checked form           $(DEX_CHECKED_ANF)'; \
		echo 'DEX plan               $(DEX_PLAN)'; \
	} >$(DEX_VALIDATION_RECEIPT)
	@cat $(DEX_VALIDATION_RECEIPT)

dex-device: dex-test $(SMALI_JAR)
	SMALI_JAR="$(CURDIR)/$(SMALI_JAR)" tests/dex/device-acceptance.sh $(DEX_FILE)

test: dex-test

verify: dex-test

clean:
	rm -rf build
