.syntax unified
.arch armv7-a
.thumb

.section .text

.global fill_red_8888
.type fill_red_8888, %function
.thumb_func
fill_red_8888:
    push    {r4-r7, lr}

    cmp     r1, #0
    ble     2f
    cmp     r2, #0
    ble     2f

    mov     r4, r0              @ row base
    mov     r5, r1              @ width in pixels
    mov     r6, r2              @ rows remaining
    lsls    r7, r3, #2          @ stride in bytes

    @ WINDOW_FORMAT_RGBA_8888 / RGBX_8888 memory bytes on little-endian ARM:
    @   ff 00 00 ff  = red, green, blue, alpha/x
    movw    r12, #0x00ff
    movt    r12, #0xff00        @ 0xff0000ff

1:
    mov     r0, r4
    mov     r1, r5

3:
    str.w   r12, [r0], #4
    subs    r1, r1, #1
    bne     3b

    add     r4, r4, r7
    subs    r6, r6, #1
    bne     1b

2:
    pop     {r4-r7, pc}
.size fill_red_8888, .-fill_red_8888


.global fill_red_565
.type fill_red_565, %function
.thumb_func
fill_red_565:
    push    {r4-r7, lr}

    cmp     r1, #0
    ble     5f
    cmp     r2, #0
    ble     5f

    mov     r4, r0              @ row base
    mov     r5, r1              @ width in pixels
    mov     r6, r2              @ rows remaining
    lsls    r7, r3, #1          @ stride in bytes
    movw    r12, #0xf800        @ RGB565 red

4:
    mov     r0, r4
    mov     r1, r5

6:
    strh.w  r12, [r0], #2
    subs    r1, r1, #1
    bne     6b

    add     r4, r4, r7
    subs    r6, r6, #1
    bne     4b

5:
    pop     {r4-r7, pc}
.size fill_red_565, .-fill_red_565

.section .note.GNU-stack,"",%progbits
