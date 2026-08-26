IDRIC ?= idris2
IDRIC_REVISION ?= 081b9cde0
ARM_CLANG ?= clang
ARM_TARGET ?= armv7a-linux-androideabi21

BACKEND_SOURCES := $(wildcard src/Backend/ARMThumb/*.idr) src/RendererPrimitives.idr backend.ipkg
DRIVER := build/exec/idric-arm-thumb
AFFINE_ASSEMBLY := build/exec/affine.arm-thumb.S
AFFINE_OBJECT := build/exec/affine.arm-thumb.o

.PHONY: check-compiler check driver example inspect assemble verify clean

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

example: $(AFFINE_ASSEMBLY)

inspect: example
	grep -q '^evaluate_affine:' $(AFFINE_ASSEMBLY)
	grep -q 'vmul.f32' $(AFFINE_ASSEMBLY)
	grep -q 'vadd.f32' $(AFFINE_ASSEMBLY)
	grep -q '^\.arch armv7-a' $(AFFINE_ASSEMBLY)
	grep -q '^\.thumb' $(AFFINE_ASSEMBLY)
	grep -q '^\.fpu vfpv3-d16' $(AFFINE_ASSEMBLY)

$(AFFINE_OBJECT): $(AFFINE_ASSEMBLY)
	$(ARM_CLANG) --target=$(ARM_TARGET) -c -fPIC -march=armv7-a -mthumb \
		-mfpu=vfpv3-d16 -mfloat-abi=softfp $(AFFINE_ASSEMBLY) -o $(AFFINE_OBJECT)

assemble: $(AFFINE_OBJECT)

verify: check inspect assemble
	file $(AFFINE_OBJECT) | grep -q 'ELF 32-bit.*ARM'

clean:
	rm -rf build
