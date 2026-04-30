# Edge Agent Roadmap

> Keep the production lessons before the firmware exists.

This roadmap separates throwaway board exploration from the future Edge
Agent architecture. Real boards exist (ESP32-WROOM, ESP32-CAM); this
repository is still a research shell.

The phases below map to the concentric-circle ecology defined in
[README — Position in the agent ecology](README.md#position-in-the-agent-ecology):
inner family, middle handshake, outer citizenship. README is the canonical
source for that model; this file just maps phases onto it.

An edge node joins the inner circle through its card, not through shared
storage.

## Phase 0 — Multi-board bring-up, outside the architecture

Goal: learn the boards without letting sample code define this project.

- Use `~/repos/3rd/esp32/zig-esp-idf-sample` as an external smoke-test
  sandbox.
- Build and flash one upstream sample only to prove the toolchain, serial
  port, reset wiring, flash size, and monitor loop.
- Treat all sample code as disposable.
- Do not copy its app structure, examples, or wrapper surface wholesale
  into this repository.
- Record only hardware facts that matter, per board:
  - chip model and revision
  - flash size, PSRAM size
  - MAC address
  - working serial port and USB-UART chip
  - reset / boot behavior
  - notable LEDs / GPIOs

Done when:

- `edge-mac`, `edge-chip`, and `edge-flash-id` work for both ESP32-WROOM
  and ESP32-CAM.
- One external sample can be flashed and monitored on at least one board.
- Each board can be recovered or reflashed repeatably.

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
  - `PROFILE.md` for NodeCard field shape
  - `ENVELOPE.md` for canonical encoding and message families
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

Recommend ESP32-CAM as the first target — its peripheral richness (camera,
PSRAM) exercises §10 and §12 from day one. ESP32-WROOM follows in 3.5.

Allowed sources:

- ESP-IDF CMake structure from the external sample, reduced to the minimum.
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
