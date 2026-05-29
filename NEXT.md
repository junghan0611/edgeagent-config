# NEXT — edgeagent-config

> Volatile next-step anchor. Durable facts move to AGENTS.md / ARCHITECTURE.md /
> BOARDS.md / commit history. This file is meant to be erased as items close.

## Direction (decided 2026-05-29)

- **M5Stack is the primary edge line.** Cheap, stackable, lots to attach
  (Grove/HY2.0, modular units). ESP is chosen for cost and peripheral density —
  the edge agent runs on ESP.
- **This repo is the single verification bench.** Every ESP / M5Stack device
  GLG buys is brought up, inspected, and recorded *here* before it counts as
  supported. Bench → BOARDS.md card → only then "supported".
- **The core stays one state machine (자판기).** Peripherals and capabilities are
  an *axis* bolted onto the core, never new cores. A "full device set" = one
  core + composed capability profiles per board. If composing a set ever tempts
  a Layer 2/3 change, that is a regression (ROADMAP Phase 3.5).

## Now — ESP32-PICO-D4 (chip side carded 2026-05-29)

Measured and recorded: **ESP32-PICO-D4 rev v1.0 on an M5Stack carrier**, LX6
dual, 4 MB in-package flash (GigaDevice c8/4016), no PSRAM, MAC
`24:a1:60:47:e7:2c`, USB-UART `0403:6001` → `/dev/ttyUSB0`, automatic RTS/DTR
download. The USB string descriptor (`M5stack` / `Hades2001`) is a measured
vendor source — so M5Stack is confirmed, but the exact M5Stack model is not.
Card is in BOARDS.md; README count + `run.sh` verified list updated.
Status: `verified: chip_id only`.

Remaining for a full Phase 0 entry:

- [ ] **GLG: which M5Stack model is this?** Chip side confirms "M5Stack carrier"
      but not the model (AGENTS §5 ask-second). With the model, the PCB-wired
      capabilities can be named. (PICO-D4 + FTDI on /dev/ttyUSB0 points at an
      older non-S3 M5 product — e.g. an M5StickC / ATOM-class or an M5Stack
      Core with an FTDI bridge — but do not assert this; confirm.)
- [ ] Flash a `hello_world` (or the `zig-esp-idf-sample`) under
      `IDF_TARGET=esp32` and confirm `app_main` is reached, then promote the
      BOARDS.md card from `chip_id only` to a full Phase 0 line.
- [ ] Confirm PCB-wired capabilities (`button_user`, `led_status`, the
      `button_boot` GPIO). Chip-side measurement cannot see PCB wiring — needs
      bring-up firmware or the confirmed model. Until then they stay `unknown`.

## When M5Stack arrives

- [ ] Pick the first M5Stack target to bring up. Candidates (see the garden 대문,
      `~/sync/org/botlog/20260222T083800`):
      - **CoreS3** — richest body (mic/spk/cam/IMU/display), the "AI friend" path
      - **AtomS3** — cheapest ESP32-S3
      - **Dial** — smart-home controller UI
- [ ] `./run.sh probe/inspect` with the right `IDF_TARGET` (S3 → `esp32s3`,
      native USB → `/dev/ttyACM0`).
- [ ] One BOARDS.md card per board, via the same 6-step procedure. Record
      capabilities from the axes table, adding a new axis only when a verified
      board genuinely needs one (e.g. CoreS3 may force `imu` / `display`, which
      the current table does not yet name).

## Device-set composition goal

- [ ] Keep BOARDS.md as the capability matrix: rows = boards, columns =
      capability axes. The "full set" is read off this matrix.
- [ ] Hold the invariant: a new board = new Layer 1 + new StaticProfile only.
      The core, card builder, and envelope never change to add a board.

## Open questions for GLG

- **NEXT.md vs the documents-map invariant (AGENTS §1):** that rule says a doc
  not linked from the map / README should not exist. NEXT.md is the universal
  volatile working anchor. Decide: commit + link it, or `.gitignore` it as a
  local-only anchor. (Recommend: gitignore — it is volatile, not architecture.)
- Which M5Stack board first?
- Power / enclosure plan for a composed set (battery, Grove hub) — out of scope
  until at least one board is bench-verified.
