# linux-fbdev-red ARMv7 Thumb-2 build receipt

Source: `tests/framebuffer/linux_fbdev_red.S`

Built in the ChatGPT cloud execution environment with:

```sh
clang --target=armv7a-linux-gnueabihf -fuse-ld=lld \
  -nostdlib -static -march=armv7-a -mthumb \
  -Wl,-e,_start -Wl,--no-dynamic-linker \
  linux_fbdev_red.S -o linux-fbdev-red.armv7-thumb2
```

Toolchain observed:

```text
clang version 17.0.0 (https://github.com/swiftlang/llvm-project.git 10999b6d034fe318f3d56c83bddb6572593a8bb0)
LLD 17.0.0 (https://github.com/swiftlang/llvm-project.git 10999b6d034fe318f3d56c83bddb6572593a8bb0)
```

Artifact inspection:

```text
ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), statically linked, not stripped
Class: ELF32
Data: 2's complement, little endian
Machine: ARM
Entry point address: 0x200f9
Flags: 0x5000200, Version5 EABI, soft-float ABI
Size: 1976 bytes
SHA-256: 17a378925bece764b6403d5cd17b4dccbf368382aeabff45e97eecb7519e9e6c
```

This receipt proves cross-compilation and ELF identity only. It does not claim that the program has executed against an fbdev device or changed a physical Android display.
