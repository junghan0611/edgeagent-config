# Architecture — Edge Agent

This document is the one-page synthesis of every architectural
decision currently locked in this repository. The other documents go
into specifics; this one shows the whole shape at once.

> If you are reading this for the first time, read this page first,
> then [AGENTS.md](AGENTS.md) for the agent-facing rules and
> [INVARIANTS.md](INVARIANTS.md) for the hard rules. The spec
> contracts live under [spec/](spec/).

## 1. Identity — what an edge node is

```
I am the Edge.
I have sensors and actuators attached to my body.
I observe, transition, and speak to peers.
```

An edge node is not a dumb peripheral. It is a small agent with:

- composite identity (chip + MAC + role + hardware profile, never a
  single field)
- local state owned in one place
- sensor / actuator bindings
- a typed time model
- event ingress + output actions
- A2A communication
- observable health
- self-description through a card

## 2. Shape — 자판기 (vending machine)

The shape of that agent is a 자판기 — a vending machine.

- **Same input, same output.** A pure transition function on
  `(state, event, now_ms)`; no hidden side branches, no clock as a
  side effect (the clock is an explicit argument).
- **One state owner, one loop.** Other modules and callbacks never
  hold a mutable pointer into state. They push events; the loop
  transitions state.
- **Periodic self-inspect.** Every tick the node asks itself "지금 내
  상태는? 지금 무엇을 해야 하는가?" and bounds work into one frame.
  Default tick is 100 ms.

This is the same posture the internal production Zig reference (see
[AGENTS.md §1.1](AGENTS.md#11-external-reference-repos)) ships in
production today. The 자판기 framing is the input-side mirror of the
"프린터 비유" used there: same coin → same can.

## 3. The 4-layer model

```text
Layer 4. Transport (replaceable)
   ESP-NOW · MQTT · BLE · CoAP — carrier only.

Layer 3. A2A Contract (pure)
   NodeCard, Capability query, Event, Output ack — canonical envelope.

Layer 2. State Machine Core (Zig, hardware-agnostic)
   transition(state, event, now_ms) -> (next_state, actions[])
   The core loop is a six-stage 100 ms conveyor (see §4 below).

Layer 1. Board Init / HAL Boundary (per-board)
   Boot, clocks, GPIO map, peripheral init.
   Callbacks emit events. Outputs drive pins.

Layer 0. Hardware
   ESP32-WROOM, ESP32-CAM, ESP32-S3 audio board, future MCUs.
   Per-board cards: see BOARDS.md.
```

Hard rules at this layering:

- The core does not know which board it runs on.
- A new board adds a new Layer 1 plus a new `StaticProfile`. The core
  never changes.
- Callbacks at Layer 1 emit events; they never mutate state directly.
- Outputs from Layer 2 drive Layer 1; Layer 1 reports outcomes as
  new events.
- Time values carry their axis in the type name (`MonotonicMs`,
  `Tick32`, ...).
- A2A messages (Layer 3) are events or outputs, not hidden side
  effects.
- Transport choice (Layer 4) does not change the envelope.

## 4. The 100 ms conveyor (Layer 2 expanded)

Every tick the loop runs six stages, each doing one job:

```
poll low-level events
  → detector (raw → meaningful events)
  → checkTimeouts (pure, state-entry timestamps; no timer slots)
  → transition (pure; the heart of the vending machine)
  → view derivation (pure: card snapshot, LED, ...)
  → I/O dispatch (apply view, run actions)
  → sleep until next 100 ms tick
```

Notes on each stage:

1. **poll low-level events** — Layer 1 callbacks have queued raw
   events (button edge, raw IO). Drain into a buffer.
2. **detector** — concept layer that lifts raw events into meaningful
   events (e.g. "button edge stream" → "factory reset requested").
   In code, detector and core share one `Event` union; the two-tier
   framing is design-time clarity, not necessarily a directory split.
3. **checkTimeouts** — pure function over `(state, now_ms)` returning
   a fixed-size `[N]?Event`. No timer table in the I/O layer; every
   state branch records its entry time (`*_enter_ms`). Deterministic,
   testable.
4. **transition** — `transition(state, event, now_ms) → (next_state,
   actions[])`. Pure. Same input, same output.
5. **view derivation** — pure functions on `(state, time)`, e.g.
   `getLedState`, `buildNodeCard`. The card builder is one such view.
6. **I/O dispatch** — apply the derived view, execute the queued
   actions. The only stage that touches the world.

## 5. Card-first principle

Every node speaks itself through a card. The card has three parts:

```
NodeCard = StaticProfile        (boot-stable: compile-time + values
                                 read once during board init)
         + RuntimeCapability    (current mode, peripherals on, GPIOs
                                 owned; changes when mode changes)
         + Health               (boot_epoch, uptime, free internal/
                                 PSRAM, last error, time since
                                 last A2A)
```

The card is built by the core, not by the boundary. Boards inject
only the static profile. A board that serializes itself directly to
a transport is a bug.

Capabilities are **an axis**, not a board enumeration. "Microphone"
or "speaker" is a capability that any board with the wiring may
advertise, on any chip with the necessary peripherals. Per-board
capability cards live in [BOARDS.md](BOARDS.md); the schema lives in
[spec/PROFILE.md](spec/PROFILE.md).

## 6. Survival rules carried in (from production reference)

These rules survived a Zig production iteration and are recorded
here as forewarning before the first firmware code lands. Two of
them are deadlock-prevention rules from real production incidents.

1. **Single state owner.** One state struct, one `var`, one loop.
2. **Pure transition.** No I/O, no thread, no clock side effect
   inside the transition.
3. **100 ms self-inspect.** The loop above.
4. **Threads only in I/O.** Core / types / hub modules are
   thread-free. OS threads, callbacks, SDK contexts live in I/O.
5. **Timers as state-entry timestamps, not slots.** No timer table
   in I/O.
6. **Event SSOT.** One `Event` union; layering is conceptual.
7. **One config-as-SSOT file** for constants, command strings,
   timeouts, JSON templates.
8. **Deadlock guard A:** never log or push events while holding a
   mutex. Record a flag under lock; log after unlock.
9. **Deadlock guard B:** single integration point per device update.
   One callback mutates state and publishes the upstream notification
   (single source, single publisher).

The full extraction with rationale lives in
[NOTES-EXTERNAL.md](NOTES-EXTERNAL.md) under the 2026-05-06 posture
note.

## 7. SSOT — sources of truth

Information in this repository comes from sources that must not be
crossed:

- **Measurable** (얻어올 facts): chip identity, eFuse, USB descriptor,
  firmware boot log, file contents, git history, build artifacts.
  The agent gathers these directly via `./run.sh inspect` and similar
  surfaces.
- **Asserted by GLG** (물어볼 facts): board model name when the PCB
  does not burn one, design intent, naming, scope. The agent must
  ask.
- **Schema SSOT** (documented contracts): NodeCard fields in
  [spec/PROFILE.md](spec/PROFILE.md), envelope shape in
  [spec/ENVELOPE.md](spec/ENVELOPE.md), companion identity in
  [spec/REGISTRY.md](spec/REGISTRY.md), validation pipeline in
  [spec/INGEST.md](spec/INGEST.md).
- **Hard rules SSOT**: [INVARIANTS.md](INVARIANTS.md) — laws on
  time, state, transport, and the card. Not negotiable.

The full measurement-vs-assertion rule is
[AGENTS.md §5](AGENTS.md#5-source-of-truth-measure-first-ask-second).

## 8. The conveyor that builds the card

Tying §4, §5, §7 together: the card is one of the views the
conveyor derives from the state. Every 100 ms, the loop has the
opportunity to build a fresh `NodeCard` from `(StaticProfile,
HubState, now_ms)` and either store it for the next A2A query or
push it as an output. `StaticProfile` is filled once at Layer 1
boot from measurable surfaces (chip → eFuse → board pins). The
agent never invents a field the chip does not yet expose.

That is the whole architecture: one state, one loop, one conveyor,
one card, two source kinds.

## 9. See also

- [AGENTS.md](AGENTS.md) — agent-facing rules (project phase,
  identity, source-of-truth, multi-board posture, time discipline,
  Zig discipline, "before adding code" checklist)
- [INVARIANTS.md](INVARIANTS.md) — hard rules (time, state,
  transport, card)
- [BOARDS.md](BOARDS.md) — verified board inventory + capability
  axes
- [NOTES-EXTERNAL.md](NOTES-EXTERNAL.md) — patterns read from
  external references (no code is imported)
- [ROADMAP.md](ROADMAP.md) — phase plan from board bring-up to hub
  bridge
- spec/ — protocol/schema contracts:
  [PROFILE](spec/PROFILE.md) ·
  [ENVELOPE](spec/ENVELOPE.md) ·
  [REGISTRY](spec/REGISTRY.md) ·
  [INGEST](spec/INGEST.md)
