.syntax unified
.arch armv7-a
.thumb
.text

.global _start
.type _start, %function
.thumb_func
_start:
        @ Pixel (0, 0) = red through generated Idriç code.
        ldr     r0, =surface
        movs    r1, #0
        movs    r2, #0
        ldr     r3, =0x0000f800
        bl      rgb565_put_pixel_generated

        ldr     r1, =0x0000f800
        cmp     r0, r1
        bne     fail_1
        ldr     r1, =framebuffer
        ldrh    r0, [r1, #0]
        ldr     r2, =0x0000f800
        cmp     r0, r2
        bne     fail_2

        @ Pixel (3, 2) must land at 2*12 + 2*3 = byte offset 30.
        ldr     r0, =surface
        movs    r1, #3
        movs    r2, #2
        ldr     r3, =0x000007e0
        bl      rgb565_put_pixel_generated

        ldr     r1, =0x000007e0
        cmp     r0, r1
        bne     fail_3
        ldr     r1, =framebuffer
        ldrh    r0, [r1, #30]
        ldr     r2, =0x000007e0
        cmp     r0, r2
        bne     fail_4

        @ Adjacent pixels, padded bytes, and outer guards are untouched.
        ldrh    r0, [r1, #24]
        cmp     r0, #0
        bne     fail_5
        ldrh    r0, [r1, #32]
        cmp     r0, #0
        bne     fail_6
        ldrh    r0, [r1, #8]
        cmp     r0, #0
        bne     fail_7
        ldrh    r0, [r1, #10]
        cmp     r0, #0
        bne     fail_8

        ldr     r1, =guard_before
        ldrh    r0, [r1]
        ldr     r2, =0x0000a55a
        cmp     r0, r2
        bne     fail_9
        ldr     r1, =guard_after
        ldrh    r0, [r1]
        ldr     r2, =0x00005aa5
        cmp     r0, r2
        bne     fail_10

        movs    r0, #0
        b       exit

fail_1:  movs r0, #1;  b exit
fail_2:  movs r0, #2;  b exit
fail_3:  movs r0, #3;  b exit
fail_4:  movs r0, #4;  b exit
fail_5:  movs r0, #5;  b exit
fail_6:  movs r0, #6;  b exit
fail_7:  movs r0, #7;  b exit
fail_8:  movs r0, #8;  b exit
fail_9:  movs r0, #9;  b exit
fail_10: movs r0, #10

exit:
        movs    r7, #1
        svc     #0

.size _start, .-_start

.data
.p2align 2
surface:
        .word   framebuffer
        .word   36
        .word   4
        .word   3
        .word   12

.p2align 2
guard_before:
        .hword  0xa55a
framebuffer:
        .space  36, 0
guard_after:
        .hword  0x5aa5

.section .note.GNU-stack,"",%progbits
