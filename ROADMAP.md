# Edge Agent Roadmap

> Keep the production lessons before the firmware exists.

This roadmap separates throwaway board exploration from the future Edge Agent
architecture. The ESP32-WROOM board is real, but this repository is still a
research shell.

## Phase 0 — Board bring-up, outside the architecture

Goal: learn the board without letting sample code define this project.

- Use `~/repos/3rd/esp32/zig-esp-idf-sample` as an external smoke-test sandbox.
- Build and flash one upstream sample only to prove the toolchain, serial port,
  reset wiring, flash size, and monitor loop.
- Treat all sample code as disposable.
- Do not copy its app structure, examples, or wrapper surface wholesale into this
  repository.
- Record only hardware facts that matter:
  - chip model and revision
  - flash size
  - MAC address
  - working serial port
  - reset/boot behavior
  - LED GPIO if discovered

Done when:

- `edge-mac`, `edge-chip`, and `edge-flash-id` work.
- One external sample can be flashed and monitored.
- The board can be recovered or reflashed repeatably.

## Phase 1 — Edge invariants before firmware

Goal: preserve the rules that prevent production-style time and state bugs.

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
```

Rules:

- No hardware calls in the core.
- No callbacks mutating state.
- No hidden timers.
- Transitions return output actions.
- Time values must carry their axis in the type name.

First tests:

- seconds-to-ms widening boundary
- `u32` tick wrap boundary
- threshold minus one / plus one
- zero or uninitialized tick semantics
- deep-sleep / boot epoch reset assumptions

Done when:

- The core builds and tests on the host without ESP-IDF.

## Phase 3 — Minimal ESP-IDF/Zig firmware scaffold

Goal: add only the build integration needed to run the core on ESP32-WROOM.

Allowed sources:

- ESP-IDF CMake structure from the external sample, reduced to the minimum.
- Zig Xtensa toolchain from `flake.nix`.

First firmware should do only this:

- boot
- print identity and heap info
- print monotonic time once per second
- optionally blink a known GPIO
- feed events into the core and print returned outputs

Not allowed yet:

- WiFi policy
- MQTT policy
- A2A protocol design
- sensor drivers
- persistent storage policy
- complex wrapper imports

Done when:

- `edge-build`, `edge-flash`, and `edge-monitor` work for a minimal firmware.
- Host core tests still pass independently.

## Phase 4 — First real edge body

Goal: attach a small body without breaking the architecture.

- Choose two sensors or one sensor plus one actuator.
- Model sensor samples as `Event`s.
- Model actuator commands as `Output`s.
- Keep driver code outside the core.
- Add observable health output.

Done when:

- The device can say: "I am the Edge. I observe, transition, and speak."

## Phase 5 — A2A edge communication

Goal: make peer communication explicit and testable.

- Define the smallest A2A message envelope.
- Treat inbound peer messages as events.
- Treat outbound peer messages as outputs.
- Add replayable tests for message/state interactions.

Done when:

- Peer communication does not bypass the state machine.

## Standing rule

Do less than feels exciting. The first firmware should be boring enough that its
state, time, and outputs are obvious.
