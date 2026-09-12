.syntax unified
.arch armv7-a
.fpu vfpv3-d16
.thumb
.text

.global _start
.type _start, %function
.thumb_func
_start:
        @ 2 * 3 + 4 = 10
        ldr     r0, =0x40000000
        ldr     r1, =0x40400000
        ldr     r2, =0x40800000
        bl      evaluate_affine
        ldr     r1, =0x41200000
        cmp     r0, r1
        bne     fail_affine

        @ 7 - 2 = 5
        ldr     r0, =0x40e00000
        ldr     r1, =0x40000000
        bl      float32_sub_test
        ldr     r1, =0x40a00000
        cmp     r0, r1
        bne     fail_sub

        @ 8 / 2 = 4
        ldr     r0, =0x41000000
        ldr     r1, =0x40000000
        bl      float32_div_test
        ldr     r1, =0x40800000
        cmp     r0, r1
        bne     fail_div

        @ -2
        ldr     r0, =0x40000000
        bl      float32_neg_test
        ldr     r1, =0xc0000000
        cmp     r0, r1
        bne     fail_neg

        @ abs(-2) = 2
        ldr     r0, =0xc0000000
        bl      float32_abs_test
        ldr     r1, =0x40000000
        cmp     r0, r1
        bne     fail_abs

        @ sqrt(4) = 2
        ldr     r0, =0x40800000
        bl      float32_sqrt_test
        ldr     r1, =0x40000000
        cmp     r0, r1
        bne     fail_sqrt

        @ values[2] = 4
        ldr     r0, =test_values
        movs    r1, #2
        bl      float32_load_test
        ldr     r1, =0x40800000
        cmp     r0, r1
        bne     fail_load

        @ The Idriç Int32 literal 1 must lower to a real word constant.
        ldr     r0, =test_values
        bl      float32_load_second
        ldr     r1, =0x40000000
        cmp     r0, r1
        bne     fail_literal

        @ Identity and unused-argument ABI preservation.
        ldr     r0, =0x40a00000
        bl      float32_identity
        ldr     r1, =0x40a00000
        cmp     r0, r1
        bne     fail_identity

        ldr     r0, =0x40a00000
        ldr     r1, =0x3f800000
        bl      float32_first
        ldr     r1, =0x40a00000
        cmp     r0, r1
        bne     fail_first

        movs    r0, #0
        b       exit

fail_affine:
        movs    r0, #1
        b       exit
fail_sub:
        movs    r0, #2
        b       exit
fail_div:
        movs    r0, #3
        b       exit
fail_neg:
        movs    r0, #4
        b       exit
fail_abs:
        movs    r0, #5
        b       exit
fail_sqrt:
        movs    r0, #6
        b       exit
fail_load:
        movs    r0, #7
        b       exit
fail_literal:
        movs    r0, #8
        b       exit
fail_identity:
        movs    r0, #9
        b       exit
fail_first:
        movs    r0, #10

exit:
        movs    r7, #1
        svc     #0

.size _start, .-_start

.data
.p2align 2
test_values:
        .word   0x3f800000
        .word   0x40000000
        .word   0x40800000

.section .note.GNU-stack,"",%progbits
