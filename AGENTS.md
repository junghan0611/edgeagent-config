# Edge Agent — Agent Guide

**"I am the Edge."**

This repository is a documentation-first research shell for Zig-oriented
small edge agents. Do not add code, build systems, directories, or
abstractions until a human explicitly asks for them.

The current job is to preserve hard-won design invariants before firmware
exists, and to anchor the multi-board, card-first architecture before any
single board's quirks contaminate the design.

## 1. Project phase: research shell

This is not yet a template implementation. It is a place to collect the
rules that will make a future template safe.

Allowed work:

- improve `README.md`
- improve this `AGENTS.md`
- improve `INVARIANTS.md`
- improve `ROADMAP.md`
- maintain `flake.nix` as a multi-board ESP32 family bring-up shell
- add concise design notes only when requested

Do not create:

- `src/`
- `build.zig`
- CI workflows
- example firmware
- hardware-specific drivers
- transport implementations (ESP-NOW / MQTT / BLE adapters)

`flake.nix` is allowed only as a reproducible ESP32 family bring-up shell.
It is not a firmware scaffold and must not pull policy or sample
application code into this repository.

`kassane/zig-esp-idf-sample` may be used as an external reference for
ESP-IDF/Zig integration. Do not fork it wholesale into this repo. Copy only
the smallest build-system pieces when firmware work is explicitly
authorized.

Until the invariants are stable, firmware code would be noise.

## 2. Identity

A future edge node is not a dumb peripheral.

It is a small agent with:

- composite identity (chip + MAC + role + hardware profile, never a single
  field)
- local state
- sensor / actuator bindings
- a typed time model
- event ingress
- output actions
- A2A communication
- observable health
- self-description through a card

The guiding scenario:

```text
I am the Edge.
I have two sensors attached to my body.
I observe, transition, and speak to peers.
```

## 3. Architecture direction: the 4-layer model

```text
Layer 4. Transport (replaceable)
   ESP-NOW · MQTT · BLE · CoAP — carrier only.

Layer 3. A2A Contract (pure)
   NodeCard, Capability query, Event, Output ack — canonical envelope.

Layer 2. State Machine Core (Zig, hardware-agnostic)
   transition(state, event) -> next state + [output]
   card builder is a pure function of profile + state + time.

Layer 1. Board Init / HAL Boundary (per-board)
   Boot, clocks, GPIO map, peripheral init.
   Callbacks emit events. Outputs drive pins.

Layer 0. Hardware
   ESP32-WROOM, ESP32-CAM, future MCUs.
```

Rules:

- The core does not know which board it runs on.
- A new board adds a new Layer 1 plus a new static profile. The core never
  changes.
- Callbacks at Layer 1 emit events; they never mutate state directly.
- Outputs from Layer 2 drive Layer 1; Layer 1 reports outcomes as new
  events.
- Time values carry their axis in the type name (`MonotonicMs`, `Tick32`,
  ...).
- A2A messages (Layer 3) are events or outputs, not hidden side effects.
- Transport choice (Layer 4) does not change the envelope.

## 4. Card-first principle

Every node speaks itself through a NodeCard:

```text
NodeCard = StaticProfile        (board fills at compile time)
         + RuntimeCapability    (current mode, peripherals on, GPIOs owned)
         + Health               (uptime, free internal/PSRAM, last error,
                                 time since last A2A)
```

The card is built by the core, not by the boundary. Boards inject only a
static profile. This keeps self-description honest and uniform across the
family. A board that serializes itself directly to a transport is a bug.

## 5. Multi-board posture

This repository targets a board *family*, not a single device. Two boards
already matter (ESP32-WROOM, ESP32-CAM). More will follow.

Rules for board variety:

- One bring-up shell. Differences belong below the shell.
- One core. Differences belong in Layer 1 and StaticProfile, not in the
  core.
- One card envelope. Differences appear as different Capability values, not
  as different envelope shapes.
- One transport contract. ESP-NOW vs MQTT vs BLE is a Layer 4 choice; the
  envelope crossing them is identical.

If a change can be expressed only by branching the core or the envelope,
the abstraction is wrong.

## 6. Time-axis discipline

This repository exists partly because a production Zig/ARM32 system failed
at 24.855 days and had a second latent failure at 49.7 days.

Every future edge node must treat time values as typed concepts:

- wall clock
- monotonic uptime
- wrapping tick
- duration

Do not subtract values from different time axes. Do not multiply
platform-sized integers before widening. Do not treat SDK ticks as absolute
timestamps.

See `INVARIANTS.md`.

## 7. Zig discipline

Zig is explicit, but not magical.

- `isize` and `usize` are platform-dependent.
- `comptime_int` participates in the typed operand's arithmetic domain.
- `@intCast` after arithmetic does not make the arithmetic safe.
- Cast before multiplication when converting time units.
- Use wrapping arithmetic intentionally (`-%`, `+%`) for wrapping ticks.
- Boundary tests are more important than happy-path tests.

## 8. Sussman stance: flexible software

The design goal is flexible software in the Gerald Jay Sussman sense —
systems that can be understood, modified, and recomposed without losing
their structure.

Flexibility here means:

- small pieces
- explicit contracts (the card *is* the contract)
- inspectable state
- replaceable I/O
- replaceable transport
- pure transitions
- testable time behavior
- no hidden global policy

Flexibility does not mean unbounded abstraction or clever indirection.

## 9. Before adding code

Before creating the first `src/` file, answer:

1. What state does this node own?
2. What are its events?
3. What outputs can it request?
4. Which time axes exist?
5. Which values are wrapping ticks?
6. What is the A2A envelope?
7. What does its card say at boot vs at peak load?
8. Which board details belong to StaticProfile vs Layer 1 vs core?
9. What can be tested without hardware?
10. What must never happen silently?

If these are unclear, keep writing invariants instead of code.
