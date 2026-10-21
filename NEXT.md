# NEXT — edgeagent-config

> Current next-step queue only. Durable direction lives in ROADMAP.md; durable
> facts live in AGENTS.md / ARCHITECTURE.md / BOARDS.md / ROADMAP.md / commit
> history. Prune this file at the end of each repo session.

# RAIL — 현재 좌표

- [x] **1. Separate host tools from firmware dependencies; verify host evaluation/dry-run.**
- [x] **2. Confirm core/home/edge responsibility boundaries with sibling maintainers.**
- [x] **3. Finish independent review; GLG authorized commit/push on 2026-10-21.**
- [ ] **4. Define trust/role contracts before implementing connectivity.** ← CURRENT: dormant until GLG resumes; no implementation authorized

## NOW — documentation-only checkpoint

- Next session: ask which minimal trust/role decision GLG wants to resume;
  read the sibling boundaries before choosing a stack or adding code.
  The 2026-10-21 checkpoint closes documentation and shell cleanup only.
  Independent review by edge sibling `20261021T170542-52f08f` found no
  wire/schema changes; wording findings were incorporated.
  `.envrc` is a separate local change, deliberately disabled; do not stage
  or enable it.
- Host: `nix develop .#host` uses the nixos-config 26.05 revision locked at
  this checkpoint. Independent review on 2026-10-21 confirmed identical
  locked metadata and host drvPath; online-cache dry-run reported 1.6 MiB
  download / 9.6 MiB unpacked, not space reclaimed. No realisation performed.
- Firmware: plain `nix develop` / `./run.sh shell` still select the heavy
  firmware shell. It preserves upstream's 25.11 package set, now Xtensa-only;
  revised firmware evaluation/build and ZLS compatibility remain unverified.
  Do not fetch its sources, build, flash, run GC, or add compatibility shims
  without approval. Read README.md “Bring-up shell” first.
- Joint re-entry: read README.md “The three -config siblings”. Before a
  connection experiment, decide credential issuer/claim authority,
  principal-to-node binding and Hub representation scope, role issuer/local
  enforcement, and revocation/offline expiry scope. No role-grant schema,
  transport or implementation has been selected. The fake-Hub check proposed
  by core/home would not establish downstream Edge authentication.
- Coordination receipts: home maintainer `20261013T090124-1fcee9` (2026-10-21
  17:49 KST) and core maintainer `20261021T174200-0486dc` (17:50 KST) confirmed
  the documentation boundaries; edge reported its changes back through home.
- Later: check whether garden entry `20260222T083800` needs a wording update;
  its current state has not been checked.

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
