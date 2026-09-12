.syntax unified
.arch armv7-a
.thumb

@ Handwritten ARMv7 Thumb-2 reference program.
@
@ This is deliberately below libc/Bionic: it enters Linux directly with SVC.
@ It is not compiler-generated evidence.  The eventual Idriç target is the
@ source-level action "show the selected display red"; fbdev/openat/ioctl/mmap
@ are one platform implementation beneath that action.
@
@ Runtime outline:
@   open /dev/graphics/fb0, then /dev/fb0
@   query variable and fixed framebuffer information
@   mmap the framebuffer
@   construct a red pixel from the reported red bitfield
@   fill the visible 16- or 32-bit framebuffer
@   sleep for three seconds
@   exit
@
@ Exit status:
@   10  neither framebuffer path opened
@   11  FBIOGET_VSCREENINFO failed
@   12  FBIOGET_FSCREENINFO failed
@   13  unsupported pixel layout
@   14  mmap failed
@
@ A successful exit does not prove that a modern Android display actually
@ presented the pixels: SurfaceFlinger/HWC may use a different scanout path.

.equ __NR_exit,       1
.equ __NR_ioctl,     54
.equ __NR_nanosleep, 162
.equ __NR_mmap2,    192
.equ __NR_openat,   322

.equ O_RDWR,           2
.equ PROT_READ,        1
.equ PROT_WRITE,       2
.equ MAP_SHARED,       1

.equ FBIOGET_VSCREENINFO, 0x4600
.equ FBIOGET_FSCREENINFO, 0x4602

.section .text
.global _start
.type _start, %function
.thumb_func

_start:
    @ openat(AT_FDCWD, "/dev/graphics/fb0", O_RDWR, 0)
    mvn     r0, #99             @ -100 = AT_FDCWD
    ldr     r1, =fb_path_android
    movs    r2, #O_RDWR
    movs    r3, #0
    movw    r7, #__NR_openat
    svc     #0

    cmp     r0, #0
    bge     opened

    @ Fall back to the ordinary Linux fbdev path.
    mvn     r0, #99
    ldr     r1, =fb_path_linux
    movs    r2, #O_RDWR
    movs    r3, #0
    movw    r7, #__NR_openat
    svc     #0

    cmp     r0, #0
    blt     fail_open

opened:
    mov     r8, r0              @ framebuffer fd

    @ ioctl(fd, FBIOGET_VSCREENINFO, &vinfo)
    mov     r0, r8
    movw    r1, #FBIOGET_VSCREENINFO
    ldr     r2, =vinfo
    movs    r7, #__NR_ioctl
    svc     #0

    cmp     r0, #0
    bne     fail_vinfo

    @ ioctl(fd, FBIOGET_FSCREENINFO, &finfo)
    mov     r0, r8
    movw    r1, #FBIOGET_FSCREENINFO
    ldr     r2, =finfo
    movs    r7, #__NR_ioctl
    svc     #0

    cmp     r0, #0
    bne     fail_finfo

    @ This sample handles packed 16- and 32-bit pixels.
    ldr     r4, =vinfo
    ldr     r0, [r4, #24]       @ bits_per_pixel

    cmp     r0, #16
    beq     pixels_16

    cmp     r0, #32
    beq     pixels_32

    b       fail_format

pixels_16:
    movs    r12, #2             @ bytes per pixel
    b       make_red

pixels_32:
    movs    r12, #4

make_red:
    @ fb_var_screeninfo.red begins at byte 32:
    @   +32 red.offset
    @   +36 red.length
    @
    @ pixel = ((1 << red.length) - 1) << red.offset
    ldr     r1, [r4, #32]
    ldr     r2, [r4, #36]

    cmp     r2, #0
    beq     fail_format
    cmp     r2, #31
    bhi     fail_format

    movs    r3, #1
    lsl.w   r3, r3, r2
    subs    r3, r3, #1
    lsl.w   r9, r3, r1          @ r9 = red pixel

    @ mmap2(0, finfo.smem_len,
    @       PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
    ldr     r5, =finfo

    movs    r0, #0
    ldr     r1, [r5, #20]       @ smem_len
    movs    r2, #(PROT_READ | PROT_WRITE)
    movs    r3, #MAP_SHARED
    mov     r4, r8
    movs    r5, #0

    movw    r7, #__NR_mmap2
    svc     #0

    @ Linux syscall errors occupy unsigned 0xfffff001..0xffffffff.
    movw    r1, #0xf001
    movt    r1, #0xffff
    cmp     r0, r1
    bhs     fail_mmap

    mov     r8, r0              @ mapped framebuffer base

    @ Recover geometry after using r4/r5 as syscall arguments.
    ldr     r4, =vinfo
    ldr     r5, =finfo

    ldr     r11, [r5, #44]      @ line_length / stride
    ldr     r6, [r4, #0]        @ xres
    ldr     r7, [r4, #4]        @ yres
    ldr     r1, [r4, #16]       @ xoffset
    ldr     r2, [r4, #20]       @ yoffset

    @ Visible upper-left pixel:
    @ base + yoffset * line_length + xoffset * bytes_per_pixel
    mul     r2, r2, r11
    add     r10, r8, r2

    mul     r1, r1, r12
    add     r10, r10, r1

row:
    mov     r0, r10             @ current pixel
    mov     r1, r6              @ pixels remaining in row

    cmp     r12, #4
    beq     row_32

row_16:
    strh.w  r9, [r0], #2
    subs    r1, r1, #1
    bne     row_16
    b       next_row

row_32:
    str.w   r9, [r0], #4
    subs    r1, r1, #1
    bne     row_32

next_row:
    add     r10, r10, r11
    subs    r7, r7, #1
    bne     row

    ldr     r0, =sleep_time
    movs    r1, #0
    movw    r7, #__NR_nanosleep
    svc     #0

    movs    r0, #0
    b       exit

fail_open:
    movs    r0, #10
    b       exit

fail_vinfo:
    movs    r0, #11
    b       exit

fail_finfo:
    movs    r0, #12
    b       exit

fail_format:
    movs    r0, #13
    b       exit

fail_mmap:
    movs    r0, #14

exit:
    movs    r7, #__NR_exit
    svc     #0

.size _start, .-_start

.section .rodata
.align 2

fb_path_android:
    .asciz "/dev/graphics/fb0"

fb_path_linux:
    .asciz "/dev/fb0"

.align 2
sleep_time:
    .word 3
    .word 0

.section .bss
.align 4
vinfo:
    .space 160

finfo:
    .space 80
