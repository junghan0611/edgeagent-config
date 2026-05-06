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
