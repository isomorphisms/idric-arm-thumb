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

        @ Generated fillRect matches the handwritten oracle exactly:
        @ x=1, y=0, width=2, height=2, pixel=0x39e7.
        ldr     r0, =surface
        ldr     r1, =0x000039e7
        bl      rgb565_fill_rect_generated

        ldr     r1, =0x000039e7
        cmp     r0, r1
        bne     fail_11
        ldr     r1, =framebuffer
        ldrh    r0, [r1, #2]
        cmp     r0, r2
        bne     fail_12
        ldrh    r0, [r1, #4]
        cmp     r0, r2
        bne     fail_13
        ldrh    r0, [r1, #14]
        cmp     r0, r2
        bne     fail_14
        ldrh    r0, [r1, #16]
        cmp     r0, r2
        bne     fail_15

        @ Everything outside the rectangle, including row padding, survives.
        ldrh    r0, [r1, #0]
        ldr     r2, =0x0000f800
        cmp     r0, r2
        bne     fail_16
        ldrh    r0, [r1, #6]
        cmp     r0, #0
        bne     fail_17
        ldrh    r0, [r1, #8]
        cmp     r0, #0
        bne     fail_18
        ldrh    r0, [r1, #10]
        cmp     r0, #0
        bne     fail_19
        ldrh    r0, [r1, #12]
        cmp     r0, #0
        bne     fail_20
        ldrh    r0, [r1, #18]
        cmp     r0, #0
        bne     fail_21
        ldrh    r0, [r1, #20]
        cmp     r0, #0
        bne     fail_22
        ldrh    r0, [r1, #22]
        cmp     r0, #0
        bne     fail_23

        @ Row 2 and outer sentinels also survive the two-row fill.
        ldrh    r0, [r1, #30]
        ldr     r2, =0x000007e0
        cmp     r0, r2
        bne     fail_24
        ldr     r1, =guard_before
        ldrh    r0, [r1]
        ldr     r2, =0x0000a55a
        cmp     r0, r2
        bne     fail_25
        ldr     r1, =guard_after
        ldrh    r0, [r1]
        ldr     r2, =0x00005aa5
        cmp     r0, r2
        bne     fail_26

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
fail_10: movs r0, #10; b exit
fail_11: movs r0, #11; b exit
fail_12: movs r0, #12; b exit
fail_13: movs r0, #13; b exit
fail_14: movs r0, #14; b exit
fail_15: movs r0, #15; b exit
fail_16: movs r0, #16; b exit
fail_17: movs r0, #17; b exit
fail_18: movs r0, #18; b exit
fail_19: movs r0, #19; b exit
fail_20: movs r0, #20; b exit
fail_21: movs r0, #21; b exit
fail_22: movs r0, #22; b exit
fail_23: movs r0, #23; b exit
fail_24: movs r0, #24; b exit
fail_25: movs r0, #25; b exit
fail_26: movs r0, #26

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
