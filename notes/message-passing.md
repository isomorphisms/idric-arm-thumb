# Message passing as a forcing case

A large amount of useful computing is just moving information from one place to another. Treat message passing as an early acceptance program for every compiler/backend family, alongside arithmetic, display, sound, input, and timing examples.

Do not start with a chat application or a networking framework. Start by proving that some exact bytes produced at A arrive at B.

## Human-visible oracle

On machine A:

```sh
nc -l 31337
```

On machine B:

```sh
printf 'blue crate moved\n' | nc <machine-a> 31337
```

Acceptance condition: machine A receives exactly `blue crate moved\n`, once, in order. Avoid `hello`; the content should be an ordinary concrete message.

Netcat is an oracle for the behavior, not the implementation target.

## Realizations to force

Keep the semantic job the same while changing only the transport:

- process to process on one machine
- two machines on a LAN
- pipe / local socket
- TCP socket
- serial / UART between devices
- shared-memory ring or mailbox
- CPU/device memory-mapped mailbox
- FPGA/CPU mailbox or stream

This gives compiler and architecture work a concrete question: what instructions, syscalls, device operations, buffers, or handshakes are actually required to move these bytes from here to there?

## First compiler-facing slice

The source should be able to express three things plainly:

1. the bytes to send,
2. where they are going,
3. an observable success/failure result.

The first slice should not require JSON, TLS, authentication, persistence, GUI code, a large asynchronous runtime, or a chat protocol. Those are separate layers.

A useful receipt records at least:

- transport used,
- byte count requested,
- byte count actually sent,
- byte count actually received,
- exact received bytes,
- explicit failure rather than a silent fallback.

If latency is being studied, record send-to-receive elapsed time as an additional acceptance measurement.

## Later forcing case

Only after exact byte movement works should this grow into an IRC-like program: framing messages, naming peers/channels, keeping state, reconnecting, and saving history. The simple byte-transfer case should remain as the small oracle underneath it.
