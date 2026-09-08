# Idriç DEX backend

Direct Android Runtime DEX backend for Idriç.

This development line is a sibling of the ARM/Thumb backend. Both consume checked compiler forms, but DEX lowering, encoding, packaging, and acceptance are independent of ARM instruction selection and execution.

The DEX executable registers only the `dex` code generator. Its acceptance path produces `classes.dex`, validates it independently, and executes it on ART. ARM source modules, ARM emulation, and QEMU are not part of the DEX build or correctness receipt.

See `src/Backend/DEX/README.md` and `tests/dex/README.md` for the current executable slice and evidence layers.
