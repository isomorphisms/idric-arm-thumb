.syntax unified
.arch armv7-a
.thumb
.text

.global rgb565_put_pixel
.type rgb565_put_pixel, %function
.thumb_func
rgb565_put_pixel:
        @ r0 = base, r1 = stride bytes, r2 = x, r3 = y
        @ fifth AAPCS word at caller sp = RGB565 pixel (low 16 bits)
        push    {r4, lr}
        mla     r12, r3, r1, r0
        add.w   r12, r12, r2, lsl #1
        ldrh    r4, [sp, #8]
        strh    r4, [r12]
        pop     {r4, pc}
.size rgb565_put_pixel, .-rgb565_put_pixel

.global rgb565_fill_rect
.type rgb565_fill_rect, %function
.thumb_func
rgb565_fill_rect:
        @ r0 = base, r1 = stride bytes, r2 = x, r3 = y
        @ caller stack: width, height, RGB565 pixel (one word each)
        push    {r4-r7, lr}
        ldr     r4, [sp, #20]
        ldr     r5, [sp, #24]
        ldr     r6, [sp, #28]
        cmp     r4, #0
        beq     .Lfill_done
        cmp     r5, #0
        beq     .Lfill_done
        mla     r7, r3, r1, r0
        add.w   r7, r7, r2, lsl #1
.Lfill_row:
        mov     r12, r7
        mov     r3, r4
.Lfill_pixel:
        strh    r6, [r12]
        adds    r12, r12, #2
        subs    r3, r3, #1
        bne     .Lfill_pixel
        add     r7, r7, r1
        subs    r5, r5, #1
        bne     .Lfill_row
.Lfill_done:
        pop     {r4-r7, pc}
.size rgb565_fill_rect, .-rgb565_fill_rect

.global _start
.type _start, %function
.thumb_func
_start:
        @ Pixel (0, 0) = red.
        ldr     r0, =framebuffer
        movs    r1, #12
        movs    r2, #0
        movs    r3, #0
        sub     sp, sp, #8
        ldr     r12, =0x0000f800
        str     r12, [sp]
        bl      rgb565_put_pixel
        add     sp, sp, #8

        ldr     r1, =framebuffer
        ldrh    r0, [r1, #0]
        ldr     r2, =0x0000f800
        cmp     r0, r2
        bne     fail_1

        @ Pixel (3, 2) with padded 12-byte stride lands at 2*12 + 2*3 = 30.
        ldr     r0, =framebuffer
        movs    r1, #12
        movs    r2, #3
        movs    r3, #2
        sub     sp, sp, #8
        ldr     r12, =0x000007e0
        str     r12, [sp]
        bl      rgb565_put_pixel
        add     sp, sp, #8

        ldr     r1, =framebuffer
        ldrh    r0, [r1, #30]
        ldr     r2, =0x000007e0
        cmp     r0, r2
        bne     fail_2
        ldrh    r0, [r1, #24]
        cmp     r0, #0
        bne     fail_3
        ldrh    r0, [r1, #32]
        cmp     r0, #0
        bne     fail_4

        @ Adjacent pixels are independent 16-bit stores.
        ldr     r0, =framebuffer
        movs    r1, #12
        movs    r2, #1
        movs    r3, #1
        sub     sp, sp, #8
        movs    r12, #31
        str     r12, [sp]
        bl      rgb565_put_pixel
        add     sp, sp, #8

        ldr     r0, =framebuffer
        movs    r1, #12
        movs    r2, #2
        movs    r3, #1
        sub     sp, sp, #8
        ldr     r12, =0x0000ffff
        str     r12, [sp]
        bl      rgb565_put_pixel
        add     sp, sp, #8

        ldr     r1, =framebuffer
        ldrh    r0, [r1, #14]
        cmp     r0, #31
        bne     fail_5
        ldrh    r0, [r1, #16]
        ldr     r2, =0x0000ffff
        cmp     r0, r2
        bne     fail_6

        @ Fill x=1..2, y=0..1. Width=2, height=2, color=0x39e7.
        @ The 4-pixel logical row occupies 8 bytes, but stride is 12.
        ldr     r0, =framebuffer
        movs    r1, #12
        movs    r2, #1
        movs    r3, #0
        sub     sp, sp, #16
        movs    r12, #2
        str     r12, [sp, #0]
        str     r12, [sp, #4]
        ldr     r12, =0x000039e7
        str     r12, [sp, #8]
        bl      rgb565_fill_rect
        add     sp, sp, #16

        ldr     r1, =framebuffer
        ldr     r2, =0x000039e7
        ldrh    r0, [r1, #2]
        cmp     r0, r2
        bne     fail_7
        ldrh    r0, [r1, #4]
        cmp     r0, r2
        bne     fail_8
        ldrh    r0, [r1, #14]
        cmp     r0, r2
        bne     fail_9
        ldrh    r0, [r1, #16]
        cmp     r0, r2
        bne     fail_10

        @ Pixels and padding outside the rectangle must remain untouched.
        ldrh    r0, [r1, #0]
        ldr     r2, =0x0000f800
        cmp     r0, r2
        bne     fail_11
        ldrh    r0, [r1, #6]
        cmp     r0, #0
        bne     fail_12
        ldrh    r0, [r1, #8]
        cmp     r0, #0
        bne     fail_13
        ldrh    r0, [r1, #10]
        cmp     r0, #0
        bne     fail_14
        ldrh    r0, [r1, #12]
        cmp     r0, #0
        bne     fail_15
        ldrh    r0, [r1, #18]
        cmp     r0, #0
        bne     fail_16
        ldrh    r0, [r1, #20]
        cmp     r0, #0
        bne     fail_17
        ldrh    r0, [r1, #22]
        cmp     r0, #0
        bne     fail_18

        @ Row 2 and both outer sentinels also survive the fill.
        ldrh    r0, [r1, #30]
        ldr     r2, =0x000007e0
        cmp     r0, r2
        bne     fail_19
        ldr     r1, =guard_before
        ldrh    r0, [r1]
        ldr     r2, =0x0000a55a
        cmp     r0, r2
        bne     fail_20
        ldr     r1, =guard_after
        ldrh    r0, [r1]
        ldr     r2, =0x00005aa5
        cmp     r0, r2
        bne     fail_21

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
fail_21: movs r0, #21

exit:
        movs    r7, #1
        svc     #0

.size _start, .-_start

.data
.p2align 2
guard_before:
        .hword  0xa55a
framebuffer:
        .space  36, 0
guard_after:
        .hword  0x5aa5

.section .note.GNU-stack,"",%progbits
