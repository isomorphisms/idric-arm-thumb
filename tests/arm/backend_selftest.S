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

        @ The fourth one-word argument crosses in r3 and must survive unchanged.
        ldr     r0, =0x3f800000
        ldr     r1, =0x40000000
        ldr     r2, =0x40400000
        ldr     r3, =0x40a00000
        bl      float32_fourth
        ldr     r1, =0x40a00000
        cmp     r0, r1
        bne     fail_fourth

        @ All four argument registers participate: 1 + 2 + 3 + 4 = 10.
        ldr     r0, =0x3f800000
        ldr     r1, =0x40000000
        ldr     r2, =0x40400000
        ldr     r3, =0x40800000
        bl      float32_sum_four
        ldr     r1, =0x41200000
        cmp     r0, r1
        bne     fail_sum_four

        @ Exact signed-zero behavior is part of the Float32 bit contract.
        ldr     r0, =0x00000000
        bl      float32_neg_test
        ldr     r1, =0x80000000
        cmp     r0, r1
        bne     fail_neg_zero

        ldr     r0, =0x80000000
        bl      float32_abs_test
        ldr     r1, =0x00000000
        cmp     r0, r1
        bne     fail_abs_zero

        @ 1.5 - 0.5 = 1.0 exactly in binary32.
        ldr     r0, =0x3fc00000
        ldr     r1, =0x3f000000
        bl      float32_sub_test
        ldr     r1, =0x3f800000
        cmp     r0, r1
        bne     fail_fraction

        @ -3 / 2 = -1.5 exactly in binary32.
        ldr     r0, =0xc0400000
        ldr     r1, =0x40000000
        bl      float32_div_test
        ldr     r1, =0xbfc00000
        cmp     r0, r1
        bne     fail_negative_div

        @ Indexed buffer load preserves an arbitrary exact Float32 bit pattern.
        ldr     r0, =edge_values
        movs    r1, #1
        bl      float32_load_test
        ldr     r1, =0xbfc00000
        cmp     r0, r1
        bne     fail_edge_load

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
        b       exit
fail_fourth:
        movs    r0, #11
        b       exit
fail_sum_four:
        movs    r0, #12
        b       exit
fail_neg_zero:
        movs    r0, #13
        b       exit
fail_abs_zero:
        movs    r0, #14
        b       exit
fail_fraction:
        movs    r0, #15
        b       exit
fail_negative_div:
        movs    r0, #16
        b       exit
fail_edge_load:
        movs    r0, #17

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
edge_values:
        .word   0x3f000000
        .word   0xbfc00000
        .word   0x80000000

.section .note.GNU-stack,"",%progbits
