# NEXT — edgeagent-config

> Current next-step queue only. Durable direction lives in ROADMAP.md; durable
> facts live in AGENTS.md / ARCHITECTURE.md / BOARDS.md / ROADMAP.md / commit
> history. Prune this file at the end of each repo session.

## Now — document alignment

- [ ] Review the current README.md / AGENTS.md / ROADMAP.md alignment with GLG.
      ROADMAP.md now owns the durable M5Stack-first direction; NEXT.md should
      stay as the actionable queue.
- [ ] If the wording feels right, commit the documentation cleanup.
- [ ] After commit, update the garden 대문 note `20260222T083800` if any public
      wording changed materially.

## ESP32-PICO-D4 path — promote from `chip_id only`

- [ ] **GLG: physically confirm the exact M5Stack model/carrier.** Chip side
      cannot identify the PCB. Use case label, silkscreen, order history, or
      photo if possible. Record the result as `declared by GLG` unless firmware
      or vendor-burned data exposes it.
- [ ] Flash `hello_world` or `zig-esp-idf-sample` under `IDF_TARGET=esp32` and
      confirm `app_main` is reached; then promote the BOARDS.md card from
      `chip_id only` to full Phase 0.
- [ ] Confirm PCB-wired capabilities (`button_user`, `led_status`, physical
      `button_boot`, and any display/buzzer/IR/battery axes if the model has
      them). Add new capability axes only when a bench-observed board forces
      them.

## Next M5Stack body

- [ ] Pick the first M5Stack target to bring up:
      - **CoreS3** — richest body (mic/spk/cam/IMU/display), AI-friend path
      - **AtomS3** — cheapest ESP32-S3 body
      - **Dial** — smart-home controller UI
      - **StickC Plus2** — small display + IR/buzzer/battery path
- [ ] `./run.sh probe/inspect` with the right `IDF_TARGET` (S3 → `esp32s3`,
      native USB → `/dev/ttyACM0`, bridged UART → `/dev/ttyUSB0`).
- [ ] Add one BOARDS.md card per board via the procedure in BOARDS.md. Keep
      capability names as axes, not board-specific branches.

## Repo hygiene before commit

- [ ] Run `./run.sh boards` and `./run.sh targets`.
- [ ] Run markdown local-link sanity check.
- [ ] Run `git diff --check`.
