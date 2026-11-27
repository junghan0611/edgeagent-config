# edgeagent-config

> I am the Edge.

A public, Zig-oriented project for a **common edge firmware core**. The goal is a small state machine whose roles come from the capabilities and functions composed around it, not from the name of its board. ESP32 / M5Stack is the first bench, not the limit of the design.

**Today:** architecture and protocol drafts, an ESP32 bring-up shell, and a host-only Python/CBOR smoke test. There is no Zig core, cross-platform runtime, or deployable firmware in this repository yet.

## One core, different roles

Each node owns its local state. A pure transition takes `(state, event, now)` and returns the next state and action requests. The surrounding I/O executes requests and reports what happened. Clocks, drivers, links, and platform names stay outside the common transition. The product's assembly point binds the functions to capabilities and decides which requests may flow between them.

A local controller and a network helper illustrate the split:

- **Controller:** owns local control and decides what to accept or reject. In this composition it is not directly connected to the network; the helper is the server-facing node.
- **Helper:** can ask what is available now, relay requests, and report confirmed results to a server. A helper can run on an MCU or a Linux-class host without sharing a runtime or HAL with the controller.

What a node advertises is not permission to use it. What was open during discovery may be closed by the time a request reaches the owner. Delivery, acceptance, completion, and a fresh state observation are distinct facts, each with its source. Querying the owner for a result is the baseline; completion notifications are optional. After restart or disconnection, query before drawing a conclusion, leave unconfirmed results unknown, and do not automatically replay pending requests. Waiting for a result must not block unrelated work.

**Public here:** the common state-machine contract, synthetic examples, and offline verification. **Product-owned:** custom capability specifications and policies, target bindings, deployment and recovery decisions, and hardware/safety evidence. The public core and its tests must stand without product code, customer material, or private fixtures.

## What we verify first

The next design checkpoint is a deterministic host replay with a supplied monotonic clock and synthetic capabilities: correlate crossed responses, distinguish a deadline from a late response, and exercise a controller/helper pair across disconnection and restart. A replay verifies the given event order and state/action trace, not real-time behavior, physical outcomes, or safety. It does not require a card, transport, or shared scheduler.

The existing `./run.sh hello-edge` is a separate smoke test: a host master exchanges CBOR envelopes with a Python fake edge on stdin/stdout. It is not that replay harness. See [ROADMAP.md](ROADMAP.md) for scope and [NEXT.md](NEXT.md) for the next step.

## The three -config siblings

| Repository | Intended responsibility |
| --- | --- |
| [coreagent-config](https://github.com/junghan0611/coreagent-config) | Server-side identity, authorization, registration, connection lifecycle, and revocation |
| [homeagent-config](https://github.com/junghan0611/homeagent-config) | Hub/vendor base, radio and protocol services, and connection client packaging |
| **edgeagent-config** | Common edge state machine, capability composition, host verification, and optional peer-facing projections |

These are responsibility boundaries, not implemented connectivity. A NodeCard describes a node; it does not authenticate it or grant permissions. An authenticated Hub does not prove the independent identity of downstream Edges. Binding a reported identity to an authenticated principal must be explicit. A future authenticated role grant is separate from both the local composition of functions and the descriptive `firmware_role` field. Credential issuance, principal binding, local admission, and revocation remain open.

## Position in the agent ecology

This work grew out of a broader conversation about [how agents meet](https://notes.junghanacs.com/botlog/20260311T134429): inner family (existing relationships), middle handshake (introductions across families), and outer citizenship (platform-independent identity, a longer-term direction). Cards can make nodes describable within the family; they do not admit nodes or grant authority. An edge agent can observe, keep state, or speak to peers without running an AI model or exposing its local control loop to the network.

## ESP32 bring-up bench

[BOARDS.md](BOARDS.md) records the measured boards and limits of each observation. ESP32-WROOM, ESP32-CAM, and an ESP32-S3 audio board reached Phase 0 using external samples. The ESP32-PICO-D4 via an M5Stack-labeled USB-UART path is chip-identified only.

```bash
./run.sh boards          # measured board lineup and verification status
./run.sh targets         # ESP-IDF target families and shell limits
./run.sh hello-edge      # host-only Python / CBOR smoke; no board
nix develop .#host       # small host shell, no ESP-IDF toolchain
./run.sh shell esp32s3   # ESP32 bench shell; may fetch ESP-IDF and toolchains
```

Plain `nix develop` selects the ESP32 bench shell. It currently provides Xtensa targets (`esp32`, `esp32s2`, `esp32s3`) and is not a claim of support for other MCU families or Linux firmware deployment. Use `./run.sh probe <target>` or `./run.sh inspect <target>` only with an intended connected board; follow [BOARDS.md](BOARDS.md) and the sample procedure in [NOTES-EXTERNAL.md](NOTES-EXTERNAL.md). Keep `.envrc` disabled when automatic shell entry is not wanted.

## Read next

- [ARCHITECTURE.md](ARCHITECTURE.md) — common core, composition, boundaries, and projections
- [INVARIANTS.md](INVARIANTS.md) — state ownership, typed time, and interface rules
- [ROADMAP.md](ROADMAP.md) · [NEXT.md](NEXT.md) · [CHANGELOG.md](CHANGELOG.md) — direction, next step, and releases
- [AGENTS.md](AGENTS.md) · [NOTES-EXTERNAL.md](NOTES-EXTERNAL.md) — contribution gates and read-only references
- [PROFILE](spec/PROFILE.md) · [ENVELOPE](spec/ENVELOPE.md) · [REGISTRY](spec/REGISTRY.md) · [INGEST](spec/INGEST.md) — existing peer-facing contracts; not a prerequisite for core replay
