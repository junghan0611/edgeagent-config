# Edge Agent — Agent Guide

**"I am the Edge."**

This repository is a documentation-first research shell for Zig-oriented small
edge agents. Do not add code, build systems, directories, or abstractions until a
human explicitly asks for them.

The current job is to preserve hard-won design invariants before firmware exists.

## 1. Project phase: research shell

This is not yet a template implementation. It is a place to collect the rules
that will make a future template safe.

Allowed work:

- improve `README.md`
- improve this `AGENTS.md`
- improve `INVARIANTS.md`
- maintain `flake.nix` as a bring-up shell
- add concise design notes only when requested

Do not create:

- `src/`
- `build.zig`
- CI workflows
- example firmware
- hardware-specific drivers

`flake.nix` is allowed only as a reproducible ESP32-WROOM bring-up shell. It is
not a firmware scaffold and must not pull policy or sample application code into
this repository.

`kassane/zig-esp-idf-sample` may be used as an external reference for ESP-IDF/Zig
integration. Do not fork it wholesale into this repo. Copy only the smallest
build-system pieces when firmware work is explicitly authorized.

Until the invariants are stable, firmware code would be noise.

## 2. Identity

A future edge node is not a dumb peripheral.

It is a small agent with:

- identity
- local state
- sensor/actuator bindings
- a time model
- event ingress
- output actions
- A2A communication
- observable health

The guiding scenario:

```text
I am the Edge.
I have two sensors attached to my body.
I observe, transition, and speak to peers.
```

## 3. Architecture direction

The default architecture is a pure state machine:

```text
Input Event -> transition(state, event) -> next state + output actions
```

Rules:

- Core transition code is pure.
- I/O is isolated at the boundary.
- Callbacks emit events; they do not mutate state directly.
- Timeouts are derived from state-entry timestamps.
- A2A messages are events or outputs, not hidden side effects.

## 4. Time-axis discipline

This repository exists partly because a production Zig/ARM32 system failed at
24.855 days and had a second latent failure at 49.7 days.

Every future edge node must treat time values as typed concepts:

- wall clock
- monotonic uptime
- wrapping tick
- duration

Do not subtract values from different time axes. Do not multiply platform-sized
integers before widening. Do not treat SDK ticks as absolute timestamps.

See `INVARIANTS.md`.

## 5. Zig discipline

Zig is explicit, but not magical.

Remember:

- `isize` and `usize` are platform-dependent.
- `comptime_int` participates in the typed operand's arithmetic domain.
- `@intCast` after arithmetic does not make the arithmetic safe.
- Cast before multiplication when converting time units.
- Use wrapping arithmetic intentionally (`-%`, `+%`) for wrapping ticks.
- Boundary tests are more important than happy-path tests.

## 6. Sussman stance: flexible software

The design goal is flexible software in the Gerald Jay Sussman sense: systems
that can be understood, modified, and recomposed without losing their structure.

Flexibility here means:

- small pieces
- explicit contracts
- inspectable state
- replaceable I/O
- pure transitions
- testable time behavior
- no hidden global policy

Flexibility does not mean unbounded abstraction or clever indirection.

## 7. Before adding code

Before creating the first `src/` file, answer:

1. What state does this node own?
2. What are its events?
3. What outputs can it request?
4. Which time axes exist?
5. Which values are wrapping ticks?
6. What is the A2A contract?
7. What can be tested without hardware?
8. What must never happen silently?

If these are unclear, keep writing invariants instead of code.
