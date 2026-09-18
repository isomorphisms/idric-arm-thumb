.syntax unified
.arch armv7-a
.thumb
.text

.equ __NR_exit,     1
.equ __NR_write,    4
.equ __NR_close,    6
.equ __NR_ioctl,   54
.equ __NR_openat, 322

.equ O_WRONLY, 1

.equ SNDCTL_DSP_SYNC,     0x00005001
.equ SNDCTL_DSP_SPEED,    0xc0045002
.equ SNDCTL_DSP_SETFMT,   0xc0045005
.equ SNDCTL_DSP_CHANNELS, 0xc0045006
.equ AFMT_U8, 8

.equ SAMPLE_RATE, 8000
.equ SAMPLE_COUNT, 2000
.equ CYCLES, 100
.equ HALF_PERIOD, 10

.global _start
.type _start, %function
.thumb_func
_start:
        @ openat(AT_FDCWD, "/dev/dsp", O_WRONLY, 0)
        mvn     r0, #99             @ -100 = AT_FDCWD
        ldr     r1, =dsp_path
        movs    r2, #O_WRONLY
        movs    r3, #0
        movw    r7, #__NR_openat
        svc     #0
        cmp     r0, #0
        blt     fail_open
        mov     r8, r0

        @ Request unsigned 8-bit PCM.
        ldr     r3, =pcm_format
        movs    r0, #AFMT_U8
        str     r0, [r3]
        mov     r0, r8
        ldr     r1, =SNDCTL_DSP_SETFMT
        mov     r2, r3
        movs    r7, #__NR_ioctl
        svc     #0
        cmp     r0, #0
        blt     fail_format
        ldr     r3, =pcm_format
        ldr     r0, [r3]
        cmp     r0, #AFMT_U8
        bne     fail_format

        @ Request one output channel.
        ldr     r3, =pcm_channels
        movs    r0, #1
        str     r0, [r3]
        mov     r0, r8
        ldr     r1, =SNDCTL_DSP_CHANNELS
        mov     r2, r3
        movs    r7, #__NR_ioctl
        svc     #0
        cmp     r0, #0
        blt     fail_channels
        ldr     r3, =pcm_channels
        ldr     r0, [r3]
        cmp     r0, #1
        bne     fail_channels

        @ Request an 8 kHz sample rate.
        ldr     r3, =pcm_rate
        movw    r0, #SAMPLE_RATE
        str     r0, [r3]
        mov     r0, r8
        ldr     r1, =SNDCTL_DSP_SPEED
        mov     r2, r3
        movs    r7, #__NR_ioctl
        svc     #0
        cmp     r0, #0
        blt     fail_rate

        ldr     r3, =pcm_rate
        ldr     r0, [r3]
        movw    r1, #7600
        cmp     r0, r1
        blt     fail_rate
        movw    r1, #8400
        cmp     r0, r1
        bgt     fail_rate

        @ 100 cycles * 20 samples/cycle at 8 kHz = 0.25 s at 400 Hz.
        ldr     r4, =tone_buffer
        movs    r5, #CYCLES
fill_cycle:
        movs    r6, #HALF_PERIOD
fill_high:
        movs    r0, #224
        strb    r0, [r4], #1
        subs    r6, r6, #1
        bne     fill_high

        movs    r6, #HALF_PERIOD
fill_low:
        movs    r0, #32
        strb    r0, [r4], #1
        subs    r6, r6, #1
        bne     fill_low

        subs    r5, r5, #1
        bne     fill_cycle

        ldr     r4, =tone_buffer
        movw    r5, #SAMPLE_COUNT
write_more:
        mov     r0, r8
        mov     r1, r4
        mov     r2, r5
        movs    r7, #__NR_write
        svc     #0
        cmp     r0, #0
        ble     fail_write
        add     r4, r4, r0
        sub     r5, r5, r0
        cmp     r5, #0
        bne     write_more

        @ Wait until the OSS playback queue drains.
        mov     r0, r8
        ldr     r1, =SNDCTL_DSP_SYNC
        movs    r2, #0
        movs    r7, #__NR_ioctl
        svc     #0
        cmp     r0, #0
        blt     fail_sync

        mov     r0, r8
        movs    r7, #__NR_close
        svc     #0

        movs    r0, #0
        b       exit

fail_open:
        movs    r0, #10
        b       exit
fail_format:
        movs    r0, #11
        b       exit
fail_channels:
        movs    r0, #12
        b       exit
fail_rate:
        movs    r0, #13
        b       exit
fail_write:
        movs    r0, #14
        b       exit
fail_sync:
        movs    r0, #15

exit:
        movs    r7, #__NR_exit
        svc     #0
.size _start, .-_start

.section .rodata
.align 2
dsp_path:
        .asciz "/dev/dsp"

.data
.align 2
pcm_format:
        .word AFMT_U8
pcm_channels:
        .word 1
pcm_rate:
        .word SAMPLE_RATE

.bss
.align 4
tone_buffer:
        .space SAMPLE_COUNT

.section .note.GNU-stack,"",%progbits
