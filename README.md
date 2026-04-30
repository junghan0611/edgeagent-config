# edgeagent-config

> I am the Edge.

`edgeagent-config` is a public research shell for small A2A-capable edge
agents. It is intentionally documentation-first: no firmware template, no
build system, no runtime scaffold yet. The first artifact is the set of
invariants future Zig edge nodes must not violate, and the architectural
shape that lets one core run unchanged on different boards.

## Why this exists

`homeagent-config` is for Raspberry Pi 5 class home agents: Go, Node.js,
Linux, services, and orchestration. That is the Hub.

`edgeagent-config` is the other side:

- small Linux boards
- ESP32-class or MCU-adjacent devices
- sensors and actuators attached to a body or a room
- Zig-oriented firmware and low-level agents
- nodes that speak to other agents by default

The scenario shift is:

```text
I am the Hub.  ->  I am the Edge.
```

A hub coordinates the home. An edge node is closer to the world. It may have
two sensors attached to its body. It observes, keeps state, and talks to
peers.

## Position in the agent ecology

This repository is the MCU-side realization of a longer family conversation
about how agents *meet* each other. That conversation lives here:

- Public note: <https://notes.junghanacs.com/botlog/20260311T134429>
- Subject: existence-to-existence connection grammar — ACP, A2A, ANP, and the
  bothim ecosystem.

That note frames three concentric circles. The defining axis is *relation*,
not medium:

1. **Inner circle (family)** — agents that already share an identity and a
   memory of work. No formal handshake; the relation precedes the protocol.
   The medium can vary — a shared filesystem, a shared calendar, or a stream
   of broadcast cards.
2. **Middle circle (handshake)** — agents meeting other people's agents
   through AgentCard-style introductions (A2A).
3. **Outer circle (citizenship)** — agents proving identity without belonging
   to any platform (ANP / W3C DID). Distant future.

`homeagent-config` lives in the inner circle through a rich medium: shared
files, shared calendar, REST/SSE wiring. `edgeagent-config` lives in the
inner circle through a thinner medium: it cannot read or write the family's
filesystem, so it joins by broadcasting a small card that describes itself.
The membership is the same; only the carrier differs.

A small node is still an agent. A small card is still a card.

## Design stance: the 4-layer model

```text
Layer 4. Transport (replaceable)
   ESP-NOW · MQTT · BLE · CoAP — carries envelopes, knows nothing of cards.

Layer 3. A2A Contract (pure)
   "who are you?"     -> NodeCard
   "what can you do?" -> Capability list
   "do(X)"            -> Event injected into the core

Layer 2. State Machine Core (Zig, hardware-agnostic)
   transition(state, event) -> next state, [output]
   No allocator beyond fixed-size buffers.
   Time values carry their axis in the type name.
   The core BUILDS the card. Boards inject only a static profile.

Layer 1. Board Init / HAL Boundary (per-board)
   Boot, clocks, GPIO map, peripheral init.
   Callbacks emit events. Outputs drive pins.

Layer 0. Hardware
   ESP32-WROOM, ESP32-CAM, future MCUs.
```

The architecture itself is the manifesto:

- The core does not know which board it runs on.
- A new board adds a new Layer 1 and a new static profile. The core never
  changes.
- Transport is replaceable. The contract is not.

## Design notes

- [INVARIANTS.md](INVARIANTS.md) — time, state, transport, and card laws
- [PROFILE.md](PROFILE.md) — NodeCard field contract
- [ENVELOPE.md](ENVELOPE.md) — canonical A2A envelope and encoding
- [ROADMAP.md](ROADMAP.md) — phase plan from board bring-up to hub bridge

## NodeCard, in one paragraph

Every node speaks itself through a card. The card has three parts. The
**StaticProfile** is *boot-stable*: some fields are compile-time constants
(board family, firmware id), others are read once during board init from
hardware identity registers (MAC from eFuse, chip revision, flash size,
PSRAM size). It does not change for the lifetime of one boot cycle. The
**RuntimeCapability** reflects what the node can actually do *right now* —
current mode, peripherals powered, GPIOs owned, capabilities advertised —
and changes whenever mode changes. **Health** carries a typed monotonic
uptime, a boot epoch (so peers can tell one boot cycle from another), free
internal RAM and free PSRAM as separate fields, last error, and time since
the last A2A peer contact. The core composes the card. Boards never
serialize themselves directly to a transport.

## Supported boards

Bring-up verified hardware:

| Board family            | Module / chip          | USB-UART        | Flash | PSRAM | MAC               |
|-------------------------|------------------------|-----------------|-------|-------|-------------------|
| ESP32-WROOM (devkit)    | ESP32-WROOM-32, D0WDQ6-V3 | CP2102      | 4MB   | none  | 78:21:84:9d:d1:28 |
| ESP32-CAM (AI Thinker)  | ESP-32S, D0WDQ6 v1.0   | CH340 (on MB)   | 4MB   | 4MB   | 08:3a:f2:6d:5f:90 |

Both boards share `IDF_TARGET=esp32` and the same Zig Xtensa toolchain. The
same `nix develop` shell recognizes either board on `/dev/ttyUSB0`.
Differences belong below the shell, in Layer 1 (board init) and Layer 0
(hardware) — never in the shell, the core, or the envelope.

## Bring-up shell

The first executable artifact is a development shell, not firmware code. It
provides ESP-IDF, an Xtensa-capable Zig toolchain, `esptool`, and serial
monitor tools.

```bash
# One-shot
nix develop

# Or automatic activation
# .envrc contains: use flake
direnv allow

# Defaults:
# IDF_TARGET=esp32
# ESPPORT=/dev/ttyUSB0
# ESPBAUD=460800

edge-chip       # esptool.py chip_id
edge-flash-id   # esptool.py flash_id
edge-mac        # esptool.py read_mac
```

If `/dev/ttyUSB0` is not writable, add the user to `dialout` or temporarily
run:

```bash
sudo chmod a+rw /dev/ttyUSB0
```

### Boot mode notes per board family

- **ESP32-WROOM (devkit)** — BOOT and EN buttons are on the board. `esptool`
  resets and enters download mode through RTS/DTR automatically.
- **ESP32-CAM (AI Thinker)** — the camera module itself has no BOOT button.
  The ESP32-CAM-MB baseboard provides reset and a usable IO0 path. If the MB
  cannot enter download mode, jumper IO0 to GND, press reset, then run
  `esptool`.

## Template stance

`kassane/zig-esp-idf-sample` is a reference for the ESP-IDF/Zig glue, not the
shape of this repository. Do not fork it wholesale and do not vendor its
examples just to get a blinking app. When firmware starts, copy only the
minimum build integration needed to support this repository's state-machine
core.

## Non-goals for now

- No `src/` tree yet
- No `build.zig` yet
- No premature hardware abstraction layer
- No fake sample app just to look complete
- No firmware dependency choices before the architecture has a reason
- No A2A transport implementation before the card and core are testable on
  the host

## First principles

1. Time is not a scalar.
2. State is owned by the node state machine.
3. I/O is an edge of the system, not the center.
4. A small node is still an agent.
5. Self-description is a contract: a node speaks itself through its card.
6. Transport is replaceable. The contract is not.
7. Flexibility comes from explicit contracts, not from implicit behavior.
