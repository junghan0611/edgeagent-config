# Notes from External References

This file captures patterns *read* from external sources used during the
research phase. Two kinds of external source qualify:

1. **External reference repositories** explicitly tracked in
   [AGENTS.md § 1.1 External reference repos](AGENTS.md#11-external-reference-repos).
   These are clones we keep on disk by intention.
2. **Upstream framework material** that comes through the `flake.nix`
   dev shell rather than as a checked-out clone — most importantly
   `espressif/esp-idf` (its `examples/`, `components/`, and `tools/`).
   These are not "kept on disk" in the §1.1 sense, but anything we copy
   out of them (e.g. an `examples/get-started/hello_world` tree pulled
   into `~/repos/3rd/esp32/scratch/`) is governed by the same rules.

Either way, code is read or temporarily copied for *learning*. It is
not imported into this repository.

## Rules for this file

- Capture **patterns and observations**, not code. Verbatim code does not
  belong here.
- Each note must cite the external repo and, when useful, a path inside
  it (e.g. `zig-esp-idf-sample / build.zig`).
- Notes are durable. They should still make sense after the local clone
  of an external repo is gone.
- If a note grows into a real design rule, promote it into
  `INVARIANTS.md`, `PROFILE.md`, `ENVELOPE.md`, `REGISTRY.md`, or
  `INGEST.md` and remove it from here.
- This file does not direct firmware. It only records what we learned by
  reading.

## Template

```
### YYYY-MM-DD — short title

- source:   <repo name> / <path within repo>
- context:  what we were trying to understand
- pattern:  one or two paragraphs describing the pattern, in our own
            words, never as quoted source code
- our take: how (or whether) it informs the edge agent design here
```

## Notes

### 2026-04-30 — `idf.py monitor` requires a TTY on stdin

- source:   espressif/esp-idf / `tools/idf_monitor.py` (v5.5.2)
- context:  capturing serial output of `hello_world` from a non-interactive
            background subprocess during Phase 0 smoke test.
- pattern:  `idf_monitor.py` checks that stdin is a TTY and exits with
            "Error: Monitor requires standard input to be attached to TTY"
            otherwise. A plain `bash -c 'idf.py monitor'` from a
            non-interactive runner therefore cannot capture logs. Wrapping
            the call in `script(1)` (`script -qfc "idf.py … monitor" /dev/null`)
            gives idf_monitor a fake PTY and the call succeeds. `tio` and
            `picocom` are alternatives in the dev shell, but `script -qfc`
            is the smallest change to keep `idf.py monitor` itself.
- our take: when this repository starts emitting its own NodeCard over
            serial (Phase 3), the host-side capture path used in tests
            and CI must not depend on `idf_monitor.py`. The card stream
            should be readable by a plain `cat`-style consumer (or `tio`
            in raw mode) so that automated capture does not need a PTY
            shim. This is also a small alignment with §11 "Transport is
            replaceable; the contract is not": the envelope on serial
            should not require Espressif's monitor tool to be parsed.

### 2026-04-30 — flash baud and monitor baud are different rates

- source:   espressif/esp-idf / `idf.py` driver
- context:  first attempt at `idf.py -p /dev/ttyUSB0 -b 460800 monitor`
            produced 25 seconds of garbled bytes (`x���x ...`).
- pattern:  `-b` on `idf.py` is the **esptool** rate used during flash
            (here 460800 baud, set by `flake.nix` as `ESPBAUD`). The
            **monitor** rate must match the firmware's UART console
            speed, which on stock ESP-IDF is `CONFIG_ESP_CONSOLE_UART_BAUDRATE
            = 115200`. The flake's `edge-monitor` alias deliberately
            omits `-b` so `idf.py` falls back to that. Passing `-b 460800`
            forces idf_monitor to open the port at 460800 while the chip
            keeps printing at 115200, which is why every byte appears
            corrupted.
- our take: the bring-up shell's two aliases — `edge-flash` (carries
            `-b "$ESPBAUD"`) and `edge-monitor` (no `-b`) — encode this
            split correctly. Future scripts and Phase 3 firmware tooling
            in this repo must keep the two rates separate. If we ever
            raise the console baud (e.g. for a card-emit stream), it has
            to be raised in `sdkconfig` *and* in whatever consumer reads
            the port — not via `-b` on `idf.py monitor`.

### 2026-04-30 — `hello_world` ships a 2MB flash assumption

- source:   espressif/esp-idf / `examples/get-started/hello_world` (v5.5.2)
- context:  flashing the example to ESP32-CAM (4MB flash). Bootloader
            log: `SPI Flash Size : 2MB` and warning
            `Detected size(4096k) larger than the size in the binary
            image header(2048k). Using the size in the binary image
            header.`
- pattern:  the example's default `sdkconfig` sets
            `CONFIG_ESPTOOLPY_FLASHSIZE_2MB=y`. Even though `esptool`
            correctly detects 4MB on the chip, the bootloader image
            header carries 2MB and the runtime honours the smaller of
            the two. Using the full chip requires
            `CONFIG_ESPTOOLPY_FLASHSIZE_4MB=y` in `sdkconfig` (and a
            partition table sized to match).
- our take: when this repository's first firmware lands, its
            `sdkconfig.defaults` must declare flash size matching the
            board family member it boots on, not whatever ESP-IDF's
            example happens to ship. This is also the first concrete
            example of "self-description must not lie" (INVARIANTS §9):
            a card that advertises 4MB flash on a node booted with a
            2MB image header is wrong even if the chip itself is 4MB.

### 2026-05-06 — external sample treats the ESP32 line as one family, not a fork tree

- source:   kassane/zig-esp-idf-sample (`build.zig`, `README.md`,
            `docs/getting-started.md`, `docs/build-internals.md`,
            `.github/workflows/build.yml`)
- context:  deciding whether this repository's bring-up shell should
            grow per-chip branches as new family members arrive. The
            ESP32 (LX6) → ESP32-S3 (LX7) jump is the first such jump
            for us, and we want this repo to remain an honest basecamp
            for the whole ESP edge line, not a single-board scaffold.
- pattern:  the sample supports the entire current ESP32 line
            (`esp32`, `esp32s2`, `esp32s3`, `esp32c2`, `c3`, `c5`,
            `c6`, `c61`, `h2`, `h21`, `h4`, `p4`) through three
            single-axis toggles, not branches.
            (1) **Target switch**: `idf.py set-target <chip>` rewrites
            `sdkconfig` for that chip; there is no per-chip CMake
            project or build directory hierarchy. The CI matrix
            (`.github/workflows/build.yml:36`) iterates the same
            build over chip names.
            (2) **sdkconfig overlay**: a base `sdkconfig.defaults`
            plus optional `sdkconfig.defaults.<target>` files cover
            chip-specific deltas; differences live in declarative
            config, not in code paths
            (`docs/getting-started.md:178`, `717-719`).
            (3) **One Zig toolchain covers both Xtensa LX6 and LX7**:
            the Espressif Zig fork (`kassane/zig-espressif-bootstrap`)
            ships a single `zig` binary that handles `esp32`,
            `esp32s2`, and `esp32s3` (`docs/zig-xtensa.md:36, 109`).
            For RISC-V chips the upstream Zig already works. The
            sample's `build.zig` selects between them by chip family
            (`build.zig:243-246`), not by maintaining two toolchains.
- our take: this is the shape our bring-up shell must converge on if
            we want to be an honest ESP-line basecamp. Concretely:
            `flake.nix` keeps **one** dev shell — adding ESP32-S3
            means making `IDF_TARGET` a real toggle, not adding a
            second shell. Chip-family deltas, when they appear in a
            future firmware phase, belong in declarative config
            (`sdkconfig.defaults.<target>`) and never in branched
            code paths inside this repo. The current `zigXtensa`
            block already pulls the Espressif fork, so new Xtensa
            members (S2, S3) come for free; future RISC-V members
            will need a separate fetch, but the `mkShell` shape
            stays the same. "Board family" in this repo's
            vocabulary therefore stays a **single axis** (chip
            family), not a branching tree — and §3 ("the core does
            not know which board it runs on") is reinforced one
            layer below: even the bring-up shell must not know.

### 2026-05-06 — internal production Zig reference: the 자판기 (vending-machine) core

- source:   the internal production Zig reference recorded in
            [AGENTS.md §1.1](AGENTS.md#11-external-reference-repos)
            (its real name, repository, and target hardware live in
            PRIVATE.md; do not name them here). Two files were read:
            its agent guide and its `docs/hub-architecture-v2.md`.
- context:  before any code lands in this repository, extract the
            posture that survived the production iteration of that
            codebase so we can re-derive it here cleanly instead of
            copying its surface code.
- pattern:  하나의 자판기. A pure transition function with periodic
            self-inspect. Seven rules survive the production scars:

  (1) **Single state owner.** One `HubState` struct holds everything
      hub-wide; there is exactly one `var` of it, owned by exactly
      one loop. Other modules and callbacks never hold a `*State`
      that mutates.

  (2) **Pure transition.** `transition(state, event, now_ms) ->
      (next_state, actions[])` is a pure function. Same input, same
      output; no I/O, no thread, no clock side effect (the clock is
      an explicit argument).

  (3) **100 ms self-inspect.** The hub asks itself, every 100 ms,
      "지금 내 상태는? 지금 무엇을 해야 하는가?". Concretely a
      six-stage conveyor:

         poll low-level events
            → detector (raw → meaningful events)
            → checkTimeouts (pure, state-entry timestamps)
            → transition (pure)
            → view derivation (pure: LED state, card snapshot)
            → I/O dispatch (apply view, run actions)
            → sleep 100 ms

  (4) **Threads only in I/O.** `core/`, `types/`, `hub/` are
      thread-free: no `std.Thread`, no `sleep`, no `while(true)`,
      no blocking I/O. OS threads, callbacks, and SDK contexts
      live only in `io/real/` and `io/ffi/`. Their only job is to
      push an `Event` to the loop — never to mutate state.

  (5) **Timers as state-entry timestamps, not slots.** No timer
      table in the I/O layer. Every state branch records its
      entry time (`*_enter_ms`) and `checkTimeouts(state, now_ms)`
      is a pure function returning a fixed-size `[N]?Event`.
      Deterministic, testable, no allocation.

  (6) **Event SSOT, two-tier conceptual model.** One `Event` union
      type at the code level. Internally the team thinks of
      LowLevelEvent (button edge, raw MQTT message, raw Zigbee
      callback) being lifted to HighLevelEvent (button_factory_reset,
      control_pairing_requested, ...) by a "detector" stage. In
      code, both are members of the same union; the layering is
      conceptual, not a directory split unless the code needs one.

  (7) **`config_as_ssot.zig`.** Constants, command strings,
      timeouts, JSON templates — anything the I/O layer might
      otherwise hardcode — live in a single SSOT file. The
      transition reads from it; the I/O reads from it; nobody
      invents a literal.

  Two reinforcing rules from §4 of the reference's agent guide,
  kept here as forewarning for when firmware work begins:

  - **No mutex while logging or pushing events.** Cross-deadlocks
    via the logger's own mutex have been a production bug. Record
    a flag under lock; log after unlock.
  - **Single integration point per device update.** The "pending
    transaction" pattern: device state mutates only inside one
    callback, which also publishes the upstream notification.
    Single source, single publisher.

- our take: this is the posture this repository wants for the MCU
  edge tier. Concrete absorption plan:

  - The 100 ms tick and the six-stage conveyor become the canonical
    expansion of [AGENTS.md §3 Layer 2](AGENTS.md). What was a
    single signature `transition(state, event) -> next state +
    [output]` becomes a six-stage conveyor in the agent guide.
  - "자판기" is GLG's chosen agent-facing name for this posture.
    [AGENTS.md §2 Identity](AGENTS.md) gains the vending-machine
    framing. The reference's own "프린터 비유" (the node holds the
    finished frame, each tick prints one line of it) is kin from
    the output side; the input-side framing in this repo is 자판기
    (same coin → same can).
  - Rules (4), (5), and the deadlock notes become candidates for
    `INVARIANTS.md` when the first firmware code lands. Recorded
    here so they are not forgotten in the meantime.
  - The reference's "code SSOT" (a single file holding constants,
    command strings, timeouts, JSON templates) maps onto our
    documentation SSOT (PROFILE / ENVELOPE / REGISTRY / INGEST
    schemas) plus the measurement-vs-assertion SSOT (AGENTS §5).
    When code lands here, the same single-file convention is the
    working assumption until proven inadequate.
  - Detector concept (6) maps to a future `core/detector.zig` (or
    an inline helper). The canonical event union stays in one
    place; the two-tier framing is design-time clarity, not a
    mandatory directory split.

  Nothing from the reference is copy-pasted. The Zig dialect is
  not aligned with it. What we keep is the posture, hand-derived
  inside this repository.

### 2026-05-06 — verified Phase 0 procedure for ESP32-S3 (Zig path)

- source:   kassane/zig-esp-idf-sample (`app.zig`, `flake.nix`,
            `build.zig`) + espressif/esp-idf v5.5
- context:  proving end-to-end that this basecamp can take a fresh
            ESP-line board through "build → flash → boot" without
            adding code into edgeagent-config itself, and recording
            the exact path so the next member (or board) does not
            re-derive it.
- pattern:  one-liner-per-step procedure that worked verbatim on the
            ESP32-S3 audio board verified in BOARDS.md.

    cd ~/repos/3rd/esp32/zig-esp-idf-sample
    nix develop --command bash -c '
      export IDF_TARGET=esp32s3 ESPPORT=/dev/ttyACM0
      rm -rf build sdkconfig          # clean target switch
      idf.py set-target esp32s3       # rewrites sdkconfig
      idf.py build                    # ~5 min on a cold cache
      idf.py -p /dev/ttyACM0 flash    # bootloader+partition+app
      script -qfc "idf.py -p /dev/ttyACM0 monitor" /dev/null
    '

  Notable signals on a successful run:
  - bootloader prints `ESP-IDF v5.5.0 2nd stage bootloader`,
    chip revision, eFuse block revision, SPI flash mode/size,
    full partition table — all chip-side facts accessible without
    any extra firmware. This is the §5 "measurable" surface for
    runtime board identification.
  - reset reason on the S3 over native USB-JTAG appears as
    `rst:0x15 (USB_UART_CHIP_RESET)`. Distinct from the
    `POWERON_RESET` / `SW_CPU_RESET` pair seen on UART-bridged
    ESP32-WROOM/CAM in the 2026-04-30 boot-epoch note.
  - `idf.py monitor` over native USB CDC sees the host re-enumerate
    on reset and prints "device reports readiness to read but returned
    no data … Waiting for the device to reconnect"; idf_monitor
    handles the reconnect itself. A plain `cat /dev/ttyACM0` cannot —
    this is why `./run.sh inspect` could capture only the first line
    in its 5-second window.
  - `script -qfc … /dev/null` is still the smallest wrapper that
    gives idf_monitor a TTY in non-interactive sessions
    (2026-04-30 note "idf.py monitor requires a TTY on stdin" still
    holds on the S3 path).
- our take: this is the working Phase 0 SOP for any ESP-line board.
  Switching boards means only changing `IDF_TARGET` and `ESPPORT`
  (or letting `./run.sh shell <target>` derive ESPPORT). The
  procedure is target-agnostic by construction, which is the
  basecamp guarantee we wanted: a new member with a different ESP
  chip can run the exact same six lines and reach a `Hello, world
  from Zig!` print.

### 2026-04-30 — boot epoch has a visible signature on serial

- source:   espressif/esp-idf / ROM bootloader + 2nd stage bootloader
- context:  watching `hello_world` complete one full cycle and reboot.
- pattern:  every boot prints, in order, the ROM bootloader banner
            (`ets Jun  8 2016 00:22:57`), a reset reason
            (`rst:0x1 (POWERON_RESET)` for cold boot,
            `rst:0xc (SW_CPU_RESET)` for `esp_restart()`), the 2nd
            stage bootloader header, partition table, image segments,
            heap init, and finally `app_main()`. The reset reason byte
            is stable across firmware images and survives the bootloader
            stage; only an external observer reading the serial stream
            can see the *transition* between two cycles.
- our take: this is the first concrete instance of INVARIANTS §13
            ("a card without an epoch is a sentence without a tense").
            The reset reason alone is not a boot epoch — it does not
            increase across resets — but the *transition* from
            `Restarting now.` to a fresh `ets` banner is the hardware
            event that a future card's `boot_epoch` must increment on.
            Whatever non-volatile counter we choose (RTC slow memory,
            NVS, server-assigned id) has to be advanced on exactly that
            edge, before `app_main()` returns its first event.
