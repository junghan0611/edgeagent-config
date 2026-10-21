# Edge Agent Roadmap

> Keep the production lessons before the firmware exists.

## What this document is

This is a living roadmap, not a changelog. A changelog records what shipped;
this file records the path the project is taking, including dated direction
choices that should remain visible as the plan evolves. `NEXT.md` holds only
the current working queue. When a NEXT item becomes a durable direction, move
it here or into the owning design document.

This roadmap separates throwaway board exploration from the future Edge Agent
architecture. Real boards exist (ESP32-WROOM, ESP32-CAM, ESP32-S3 audio,
ESP32-PICO-D4 / M5Stack-labeled paths); this repository is still a research
shell.

The phases below map to the concentric-circle ecology defined in
[README — Position in the agent ecology](README.md#position-in-the-agent-ecology):
inner family, middle handshake, outer citizenship. README is the canonical
source for that model; this file maps phases onto it.

An edge node joins the inner circle through its card, not through shared
storage. This describes self-description and indexing, not authenticated
admission or permission; the trust boundary is summarized in
[README — The three -config siblings](README.md#the-three--config-siblings).

## Direction log

### 2026-05-29 — M5Stack-first edge bench

- **M5Stack is the primary edge line.** Cheap, stackable ESP32 bodies with
  Grove/HY2.0 expansion are the first product family to bench. The edge agent
  lives on ESP-class bodies; the hub remains Raspberry Pi / NUC class.
- **This repo is the single verification bench.** Every ESP / M5Stack device
  GLG buys is inspected and recorded here before it counts as supported.
  Bench → BOARDS.md card → then supported.
- **The core stays one state machine (자판기).** Peripherals and capabilities are
  axes bolted onto the core, never new cores. A device set = one core +
  composed capability profiles per board. If composing a set tempts a Layer 2
  or Layer 3 change, that is a regression.
- **Measure first, ask second.** A USB descriptor can prove the USB path label;
  it cannot by itself prove the exact carrier PCB. PCB model and wiring remain
  GLG/model/firmware assertions unless a measurable surface exposes them.

Current bench snapshot:

| board/path | status | next promotion step |
| --- | --- | --- |
| ESP32-WROOM devkit | full Phase 0 | candidate simple second body |
| ESP32-CAM AI Thinker | full Phase 0 | candidate first peripheral-rich firmware |
| ESP32-S3 audio board | full Phase 0 | audio/display-class lessons |
| ESP32-PICO-D4 via M5Stack-labeled FTDI | `chip_id only` | confirm carrier/model, then flash sample |

## Phase 0 — Multi-board bring-up, outside the architecture

Goal: learn the boards without letting sample code define this project.

- Use the `zig-esp-idf-sample` external reference as a smoke-test
  sandbox. Local path, upstream URL, and read-only rules are tracked in
  [AGENTS.md § 1.1 External reference repos](AGENTS.md#11-external-reference-repos).
- Build and flash one upstream sample only to prove the toolchain, serial
  port, reset wiring, flash size, and monitor loop.
- Treat all sample code as disposable.
- Do not copy its app structure, examples, or wrapper surface wholesale
  into this repository. Patterns observed while reading it go into
  [NOTES-EXTERNAL.md](NOTES-EXTERNAL.md).
- Record only hardware facts that matter, per board:
  - chip model and revision
  - flash size, PSRAM size
  - MAC address
  - working serial port and USB-UART chip or native USB path
  - reset / boot behavior
  - PCB/model identity only when measured from a vendor surface or
    asserted by GLG because it is not chip-measurable
  - notable LEDs / GPIOs only after model or firmware confirms wiring

Done when:

- `edge-mac`, `edge-chip`, and `edge-flash-id` work for each board that
  enters [BOARDS.md](BOARDS.md) at least as `verified: chip_id only`.
- One sample from the `zig-esp-idf-sample` external reference (or an
  ESP-IDF stock example) can be flashed and monitored on every board
  promoted to full Phase 0 status.
- Each full-Phase-0 board can be recovered or reflashed repeatably.

## Phase 1 — Edge invariants before firmware

Goal: preserve the rules that prevent production-style time, state, and
self-description bugs.

- Refine `INVARIANTS.md` with ESP32-specific time axes:
  - `esp_timer_get_time()` monotonic microseconds
  - FreeRTOS tick count and tick rate
  - wall clock after SNTP
  - deep-sleep reset behavior
  - fixed-width wrapping counters
- Define the minimum vocabulary for time types:
  - `MonotonicUs`
  - `MonotonicMs`
  - `DurationMs`
  - `Tick32`
  - `WallClockMs`
- Lock §9–§13: self-description, peripheral exclusivity, transport
  replaceability, non-homogeneous memory, boot epoch / card freshness.
- Write the first contract notes:
  - `spec/PROFILE.md` for NodeCard field shape
  - `spec/ENVELOPE.md` for canonical encoding and message families
  - `spec/REGISTRY.md` for persistent identity vs boot-instance indexing
  - `spec/INGEST.md` for validation stages and projection references
- Define what must be testable on the host before hardware I/O exists.

Done when:

- The first firmware scaffold has a written contract to follow.
- Boundary tests are specified before implementation.

## Phase 2 — Minimal host-testable core

Goal: create the smallest Edge Agent core without ESP-IDF dependency.

Candidate files, only after explicit approval:

```text
src/time.zig
src/state.zig
src/event.zig
src/output.zig
src/transition.zig
src/profile.zig    # StaticProfile shape (boards fill it)
src/card.zig       # NodeCard builder, pure function of profile+state+time
```

Rules:

- No hardware calls in the core.
- No callbacks mutating state.
- No hidden timers.
- Transitions return output actions.
- Time values must carry their axis in the type name.
- The card builder is a pure function. Round-trip serialization is a host
  test.

First tests:

- seconds-to-ms widening boundary
- `u32` tick wrap boundary
- threshold minus one / plus one
- zero or uninitialized tick semantics
- deep-sleep / boot epoch reset assumptions
- card serialization round trip
- advertised capability matches mode (peripheral exclusivity)

Done when:

- The core builds and tests on the host without ESP-IDF.

## Phase 3 — First firmware on one board

Goal: add only the build integration needed to run the core on a single
board.

Recommend a peripheral-rich board as the first target — either ESP32-CAM
(camera + PSRAM, already full Phase 0) or a confirmed M5Stack CoreS3-class
board (display + audio + camera + PSRAM, once bench-verified). The point is
to exercise §10 and §12 from day one. ESP32-WROOM or a simpler M5Stack body
follows in 3.5.

Allowed sources:

- ESP-IDF CMake structure from the `zig-esp-idf-sample` external
  reference (see
  [AGENTS.md § 1.1](AGENTS.md#11-external-reference-repos)),
  reduced to the minimum.
- Zig Xtensa toolchain from `flake.nix`.

First firmware should do only this:

- boot
- print identity and heap info
- print monotonic time once per second
- emit its NodeCard once per second over serial
- optionally blink a known GPIO
- feed events into the core and print returned outputs

Not allowed yet:

- WiFi policy
- MQTT or ESP-NOW transports
- BLE GATT
- A2A network protocol implementation
- sensor drivers beyond a single proof of life
- persistent storage policy
- complex wrapper imports

Done when:

- `edge-build`, `edge-flash`, and `edge-monitor` work for a minimal
  firmware on ESP32-CAM.
- Host core tests still pass independently.
- The card emitted by the firmware round-trips back into the host parser.

## Phase 3.5 — Same firmware on the other board

Goal: prove the architecture by running the same core on a different board
with only Layer 1 and StaticProfile changes.

- Add ESP32-WROOM (or another ESP32 family member) board init.
- Reuse the entire core, card builder, and serial transport unchanged.
- Confirm that the only diff is StaticProfile + Layer 1.

Done when:

- Both boards emit the same envelope shape with different StaticProfile
  values.
- A diff that touched Layer 2 or Layer 3 to make this work would be a
  regression.

## Phase 4 — First real edge body

Goal: attach a small body without breaking the architecture.

- Choose the first sensors. ESP32-CAM gives us OV2640 for free; pair it
  with a second sensor (PIR, microphone, or ToF) appropriate to the body.
- Model sensor samples as `Event`s.
- Model actuator commands as `Output`s.
- Keep driver code outside the core.
- Add observable health output and update the card accordingly.

Done when:

- The device can say: "I am the Edge. I observe, transition, and speak."

## Phase 4.5 — Host master, single edge

Goal: prove that a master does not need to be embedded. A host-side
agent (Claude, or any process on the developer's machine) talks the
canonical envelope to a single edge over a pipe-shaped transport.
This phase makes "엣지가 살아난다" visible *before* radios, hubs, or
multiple boards exist.

This phase does not depend on Phase 4. It can run on a host-only fake
edge (a Python placeholder for the future Zig core) so the contract is
exercised before firmware is real.

Allowed sources:

- `tools/host-master/` — a host-side toy with two halves:
  - `fake_edge.py`: the seat the future Zig core will occupy. Boots
    once, fills a `StaticProfile`, runs a 100 ms self-inspect loop,
    answers the 4 envelope kinds (`card`, `query`, `event`, `ack`).
  - `master.py`: a CLI that throws envelopes at `fake_edge.py` and
    prints what comes back.
- Canonical encoding remains CBOR (per `spec/ENVELOPE.md §2`); JSON
  view is debug only.

Rules:

- The `transition()` function in `fake_edge.py` does not name
  peripherals (no `camera`, `speaker`, `pir`, `mic` in its body). It
  reads `capabilities_now` bits and event kinds only. This is the
  invariant §14 candidate from issue #1 *demonstrated in code*; not
  yet locked as text.
- No HTTP, no JSON-RPC, no a2a SDK. The decision lives in
  [issue #1](https://github.com/junghan0611/edgeagent-config/issues/1).
- The transport is stdin/stdout subprocess. It must be replaceable by
  serial (Phase 3) without rewriting the envelope.

Done when:

- `./run.sh hello-edge` produces a NodeCard from `fake_edge.py`.
- `master.py` walks the four early queries (`who_are_you`,
  `what_can_you_do`, `read_health`, `do_x=ping`) and gets sensible
  answers for each.
- A capability advertised in `capabilities_now` matches the
  `peripherals_active` story (no peripheral lying — invariant §10
  smoke test).
- Round-trip CBOR encode → wire → decode matches byte-for-byte for
  every envelope kind.

## Phase 5 — A2A transport 1: ESP-NOW broadcast

Goal: let nodes greet each other inside the family without a router.

- Encode the canonical envelope (NodeCard, Event, Output ack) into ESP-NOW
  payloads.
- Broadcast the card on a fixed interval and on capability change.
- Treat inbound ESP-NOW messages as events.
- Add fragmentation only if a transport MTU forces it; never mutate the
  envelope.

Done when:

- Two edge nodes discover each other and exchange cards without external
  infrastructure.

## Phase 6 — A2A transport 2: MQTT mirror via the hub

Goal: cross from the inner circle into the middle circle.

- The hub (`homeagent-config` family member) listens for ESP-NOW cards and
  mirrors them to MQTT topics.
- The hub's own AgentCard advertises a confederation: itself plus the edge
  nodes it represents.
- Outbound work targeted at an edge node may arrive via MQTT, get
  translated by the hub, and reach the node as ESP-NOW.
- **This is the layer where `a2a-python` or `a2a-go` SDK mounts** — the
  hub's outward face speaks full A2A protocol so external agents read
  edge confederation cards without learning ESP-NOW. The
  `a2a-samples/helloworld` shape (AgentCard + AgentSkill + JSONRPC
  routes) is the reference target. See
  [issue #1](https://github.com/junghan0611/edgeagent-config/issues/1)
  for why the edge layer itself does not import a2a SDKs.

Done when:

- An external A2A client can read an edge node's card without speaking
  ESP-NOW.
- The contract is unchanged; only the carrier differs.

## Far future — Outer circle citizenship

Goal: a node proving its identity without leaning on the family.

- Investigate `did:wba` or similar lightweight DID methods sized for MCUs.
- Burn or store a key pair such that a node can sign its own card.
- Keep this as a discussion topic until a concrete need arises.

## Standing rule

Do less than feels exciting. The first firmware should be boring enough
that its state, time, and outputs are obvious.
