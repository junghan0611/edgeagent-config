# NEXT — edgeagent-config

Direction lives in [ROADMAP.md](ROADMAP.md); released checkpoints live in
[CHANGELOG.md](CHANGELOG.md).

# RAIL — 현재 좌표

- [x] **1. ESP bench and host envelope smoke.**
- [x] **2. Widen the project to a common edge firmware frame.**
- [ ] **3. Specify a deterministic host replay.** ← CURRENT: write synthetic input/expected-output traces
- [ ] **4. Implement and run the host core.** ← PAUSED: explicit implementation approval required
- [ ] **5. Compare real target bindings and peer connectivity.** ← PAUSED: separate target, equipment, and trust decisions

# NOW — host replay design

- Current: The public core/product boundary and request/result rules are documented. The existing Python/CBOR smoke is not the replay harness.
- Next: Turn the [Phase 2 cases](ROADMAP.md#phase-2--minimal-host-testable-core) into language-neutral trace tables. Specify initial states, receive time and tie order, actions and observations, and the expected state after each input.
- Verify: Distinguish dispatch, acceptance, result, and state observation. Old responses must not close a new request; no automatic effect replay after disconnect or restart; an independent event still progresses while waiting. Use synthetic data only.
- Gate: No Zig source/build changes, transport or card changes, hardware access, or product fixtures without separate approval. Keep `.envrc` disabled unless shell entry is intended.

# LATER — separate gates

- Trust/role grants: decide issuer, principal-to-node binding, Hub representation, local enforcement, and revocation before any authenticated connectivity experiment. The sibling fake-Hub proposal would not establish downstream Edge trust.
- ESP bench: confirm the ESP32-PICO-D4 carrier/model and wiring before considering sample flash; choose and verify the next M5Stack body separately. See [BOARDS.md](BOARDS.md) for candidate status.
- Shell: ESP firmware build and ZLS compatibility after the host split remain unverified; the first replay does not need the firmware shell.
