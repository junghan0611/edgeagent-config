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

External reference repositories are tracked below in §1.1, not by name
alone. Do not fork them wholesale. Copy only the smallest build-system
pieces, and only when firmware work is explicitly authorized.

Until the invariants are stable, firmware code would be noise.

### Documents map

The whole repository at a glance, in the order a fresh reader (human
or agent) should walk it:

- [README.md](README.md) — public-facing entry point
- [ARCHITECTURE.md](ARCHITECTURE.md) — one-page synthesis of the
  current architecture; read this before editing anything
- this file (`AGENTS.md`) — rules for working in this repository
- [INVARIANTS.md](INVARIANTS.md) — hard rules; not negotiable
- [BOARDS.md](BOARDS.md) — verified board inventory + capability
  axes
- [ROADMAP.md](ROADMAP.md) — phase plan
- [NOTES-EXTERNAL.md](NOTES-EXTERNAL.md) — patterns read from
  external references (no code is imported)
- `spec/` — protocol and schema contracts (one file per contract):
  [PROFILE](spec/PROFILE.md) ·
  [ENVELOPE](spec/ENVELOPE.md) ·
  [REGISTRY](spec/REGISTRY.md) ·
  [INGEST](spec/INGEST.md)
- `PRIVATE.md` — gitignored. Internal-only context (real names of
  the internal references in §1.1). Hand-delivered, never pushed.

A document not linked from this map or from `README.md` should not
exist. Linkless documents go stale and become deprecated.

## 1.1 External reference repos

These are read-only references kept on disk. They exist to be *read*,
not imported. Anything copied from them must be the smallest
build-system glue needed, and only after firmware work is explicitly
authorized. **An agent that does not know these references will not
understand why the invariants in this repository have the shape they
do** — the references are part of the project context, not an
optional appendix.

### Open-source toolchain reference

| Name               | Local path                              | Upstream                                        | Why kept                                                            |
|--------------------|-----------------------------------------|-------------------------------------------------|---------------------------------------------------------------------|
| zig-esp-idf-sample | `~/repos/3rd/esp32/zig-esp-idf-sample`  | <https://github.com/kassane/zig-esp-idf-sample> | ESP-IDF + Zig Xtensa integration reference (build.zig + CMake glue) |

This is where Phase 0 firmware (target switch, build, flash, monitor)
actually runs — see [NOTES-EXTERNAL.md](NOTES-EXTERNAL.md)
"verified Phase 0 procedure for ESP32-S3". Per the rule below, code
does not flow back into this repository; only patterns in
`NOTES-EXTERNAL.md` do.

### Internal production reference (lessons-learned source)

There is one internal Zig production codebase this repository takes
its design lessons from. It is referenced throughout the agent guide
and the notes as **"the internal production Zig reference"**. Its
real name, repository URL, deployed product, target hardware, and
current production version live in **PRIVATE.md** (gitignored,
hand-delivered to new members alongside this repository).

What an agent needs to know about it without opening PRIVATE.md:

- It is a Zig-based always-on edge node that has shipped to
  end-customer homes. Remote-update failure means a bricked device.
- Its single-state-machine, periodic self-inspection posture
  ("나는 ___이다 — 100 ms마다 스스로에게 묻는다: 지금 내 상태는?
  지금 무엇을 해야 하는가?") is the posture this repository is
  re-instantiating for the MCU edge tier.
- The 24.855-day and 49.7-day overflow failures named in
  `INVARIANTS.md` are concrete production incidents from that
  codebase's history; the time-axis discipline in §7 exists
  because of them.

How to read this reference (per GLG): it is "양산 가려고 하다보니
지저분해진 코드" — production-bound iteration accumulated surface
noise on top of the core. Read it for the *posture* that survived
that pressure (single state machine, periodic self-inspect, typed
time, named shadow as the A2A surface), not for the surface code
itself. **Do not align Zig dialect with this reference.** The Zig
version that lands in this repository follows the bring-up shell's
toolchain (currently `kassane/zig-espressif-bootstrap`, 0.16.x);
the reference's own Zig version is not a constraint here.
Patterns are re-derived in this repo by hand; nothing is
copy-pasted across.

This reference is internal and is **not** to be linked from
`README.md` or any other public surface. Mention it only inside
agent-facing files like this one (and refer to it by the codename
above, never by its real name in any committed file).

### Rules for all references

- Treat them as read-only. Do not commit changes back upstream from
  this repo's workflow.
- Do not import their app code, examples, or wrapper surfaces into
  this repository. The card, the core, and the envelope must be
  written here, by hand.
- Patterns learned from reading them go into `NOTES-EXTERNAL.md`.
  Code does not.
- If a local path above is missing, clone the upstream into the same
  path before continuing (open-source reference) or ask GLG (internal
  reference). Do not improvise a different location.

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

### The shape: 자판기 (vending machine)

The shape of that agent is a 자판기 — a vending machine.

- **Same input, same output.** A pure transition function on
  `(state, event, now_ms)`; no hidden side branches, no clock as
  side effect (the clock is an argument).
- **One state owner, one loop.** Other modules and callbacks
  never hold a mutable pointer into state. They push events; the
  loop transitions state.
- **Periodic self-inspect.** Every tick the node asks itself
  "지금 내 상태는? 지금 무엇을 해야 하는가?" and bounds work into
  one frame. Default tick is 100 ms (per the production reference
  in §1.1; not yet pinned as an invariant for this repo).

This is the same posture the internal production Zig reference
(§1.1) ships in production today — there the same shape is named
the "프린터 비유" (the node holds a finished frame and each tick
prints one line of it). The 자판기 framing here is the input-side
mirror: same coin → same can. Both names refer to one architectural
decision: pure transition plus periodic self-inspect.

## 3. Architecture direction: the 4-layer model

```text
Layer 4. Transport (replaceable)
   ESP-NOW · MQTT · BLE · CoAP — carrier only.

Layer 3. A2A Contract (pure)
   NodeCard, Capability query, Event, Output ack — canonical envelope.

Layer 2. State Machine Core (Zig, hardware-agnostic)
   transition(state, event, now_ms) -> (next_state, actions[])
   The single core loop is a six-stage conveyor (one tick = 100 ms,
   default; see §2 "자판기"):
     poll low-level events
       → detector (raw → meaningful events)
       → checkTimeouts (pure, state-entry timestamps; no timer slots)
       → transition (pure)
       → view derivation (pure: card snapshot, LED, ...)
       → I/O dispatch (apply view, run actions)
   Card builder is one such view derivation: a pure function of
   profile + state + time.

Layer 1. Board Init / HAL Boundary (per-board)
   Boot, clocks, GPIO map, peripheral init.
   Callbacks emit events. Outputs drive pins.

Layer 0. Hardware
   ESP32-WROOM, ESP32-CAM, ESP32-S3 audio board, future MCUs.
   Per-board cards: see [BOARDS.md](BOARDS.md).
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
NodeCard = StaticProfile        (boot-stable: compile-time constants plus
                                 values read once from hardware identity
                                 registers; immutable thereafter)
         + RuntimeCapability    (current mode, peripherals on, GPIOs owned;
                                 changes when mode changes)
         + Health               (boot_epoch, uptime, free internal/PSRAM,
                                 last error, time since last A2A)
```

The card is built by the core, not by the boundary. Boards inject only the
static profile. This keeps self-description honest and uniform across the
family. A board that serializes itself directly to a transport is a bug.

"Static" here means "stable for the lifetime of one boot cycle" — not "known
at compile time". MAC is read once during board init; that is still static
for the rest of this boot.

## 5. Source of truth: measure first, ask second

Information in this repository comes from two distinct sources that
must not bleed into each other. This split is the working SSOT
discipline here: measurable facts are single-sourced from the
measurement, asserted facts are single-sourced from GLG, and the two
sources never cross.

- **얻어올 (measurable):** chip identity, eFuse blocks, USB
  descriptors, firmware boot logs, file contents, git history, build
  artifacts, anything an instrument or process can determine on its
  own. The agent gathers these directly via `./run.sh probe`,
  `./run.sh inspect`, and similar surfaces; future card surfaces will
  expose them through the `NodeCard` builder.
- **물어볼 (asserted by GLG):** board model name when the PCB does
  not burn one, installation context, intended wiring, deployment
  topology, design intent, naming, scope. No measurable surface
  carries these, so the agent must ask. They never appear
  "discovered" because there is nothing to discover.

Rules:

1. **Measure before asking.** If a fact has a measurable surface, the
   agent must try the surface first. Asking GLG for what the chip
   already knows wastes both sides and degrades trust.
2. **Asking has a shape.** When a fact has no measurable surface, the
   agent says so explicitly: "not measurable from this surface;
   please confirm X". GLG then provides the assertion, and the agent
   records it as *declared by GLG*, not as *discovered*.
3. **Measurement wins on conflict.** GLG can be wrong. If a
   GLG-asserted fact contradicts a measured one, the agent records
   the measurement and flags the contradiction; GLG decides whether
   to re-measure (instrument was wrong) or to retract the assertion
   (memory was wrong). The agent does not silently overwrite either
   side.
4. **Documents distinguish the source.** Per-instance records (board
   cards, deployment notes, runtime captures) mark each field as
   `measured`, `declared by GLG`, or `not measurable from this
   surface — recorded as <X>`. [BOARDS.md](BOARDS.md)'s ESP32-S3
   audio entry is the live example: chip facts are measured,
   capability axes are declared, the PCB model is not measurable
   from the chip side and is recorded as such.
5. **Inconvenience does not promote a measurable fact to an asserted
   one.** Surface the measurement command (`./run.sh inspect
   <target>`, `git log -1 --pretty=%H`, …) instead of asking GLG to
   type the answer.

## 6. Multi-board posture

This repository targets a board *family*, not a single device. Three
boards are currently verified (ESP32-WROOM, ESP32-CAM, an ESP32-S3
audio board) and the basecamp is shaped to accept the rest of the ESP
line through a single axis. Per-board cards — chip facts, host path,
wired capabilities — live in [BOARDS.md](BOARDS.md). The capability
axes there are the same names every board card uses; capabilities like
`audio_in` or `audio_out` are not properties of a particular chip but
of any board that wires them. Host-side entry into the basecamp goes
through `./run.sh` (`boards`, `targets`, `port`, `shell`, `probe`,
`inspect`).

Rules for board variety:

- One bring-up shell. Differences belong below the shell.
- One core. Differences belong in Layer 1 and StaticProfile, not in the
  core.
- One card envelope. Differences appear as different Capability values, not
  as different envelope shapes.
- One transport contract. ESP-NOW vs MQTT vs BLE is a Layer 4 choice; the
  envelope crossing them is identical.
- One state machine. All loops collapse into the same
  `transition(state, event) -> next state + [output]`. Boards do not
  fork the state machine; they only contribute different
  `StaticProfile` and `RuntimeCapability` values into it.

If a change can be expressed only by branching the core or the envelope,
the abstraction is wrong.

## 7. Time-axis discipline

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

## 8. Zig discipline

Zig is explicit, but not magical.

- `isize` and `usize` are platform-dependent.
- `comptime_int` participates in the typed operand's arithmetic domain.
- `@intCast` after arithmetic does not make the arithmetic safe.
- Cast before multiplication when converting time units.
- Use wrapping arithmetic intentionally (`-%`, `+%`) for wrapping ticks.
- Boundary tests are more important than happy-path tests.

## 9. Sussman stance: flexible software

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

## 10. Before adding code

Before creating the first `src/` file, answer:

1. What state does this node own?
2. What are its events?
3. What outputs can it request?
4. Which time axes exist?
5. Which values are wrapping ticks?
6. What is the A2A envelope?
7. What does its card say at boot vs at peak load?
8. Which board details belong to StaticProfile vs Layer 1 vs core?
9. Which of the answers above are measured, and which are declared by
   GLG? (See §5.) If a field has no measurable surface, document the
   assertion path before writing the code that uses it.
10. What can be tested without hardware?
11. What must never happen silently?

If these are unclear, keep writing invariants instead of code.
