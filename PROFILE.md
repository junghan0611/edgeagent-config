# NodeCard Profile

This file defines the *shape* of the edge node's self-description before any
firmware exists. It is the contract between:

- the board boundary that injects boot-stable facts,
- the Zig core that owns state,
- the transport layer that carries bytes unchanged,
- and the hub (`homeagent-config`) that ingests, mirrors, and represents edge
  nodes upstream.

The card is not a board dump. It is the smallest truthful sentence a node can
say about itself.

## 1. Composition

```text
NodeCard = StaticProfile + RuntimeCapability + Health
```

- **StaticProfile** — boot-stable identity and hardware facts.
- **RuntimeCapability** — what the node can do *right now*.
- **Health** — how well the node is currently able to keep participating.

## 2. Design rules

1. The card is built by the core, not by the board boundary.
2. A field belongs in **StaticProfile** only if it is stable for one boot
   cycle.
3. A field belongs in **RuntimeCapability** if a mode change can alter it.
4. A field belongs in **Health** if peers need it to judge freshness,
   liveness, or degraded operation.
5. The hub may mirror or summarize the card, but must keep the original card
   recoverable.

## 3. StaticProfile

Boot-stable fields: compile-time constants plus values read once during board
init and then treated as immutable until the next reset boundary.

| Field | Type idea | Meaning | Notes |
| --- | --- | --- | --- |
| `schema_version` | `u16` | Card schema version | Starts at 1 |
| `node_kind` | enum/string | `edge` for this repo | Distinguishes from hub/desktop peers |
| `board_family` | enum/string | `esp32-wroom`, `esp32-cam-aithinker`, ... | Board-level profile selector |
| `chip_family` | enum/string | `esp32`, `esp32s3`, ... | MCU family |
| `chip_revision` | small int/string | Silicon revision | Read from hardware |
| `mac` | 6 bytes | Hardware MAC | Read once from eFuse |
| `flash_bytes` | `u32` | External flash size | Boot-stable |
| `psram_bytes` | `u32` | PSRAM size, 0 if absent | Boot-stable |
| `transport_hints` | bitset/list | Supported carriers on this build | Capability hint, not current state |
| `sensor_inventory` | bitset/list | Sensors physically attached in this profile | Static possession, not current readiness |
| `actuator_inventory` | bitset/list | Actuators physically attached in this profile | Static possession |
| `firmware_role` | enum/string | `observer`, `camera-node`, `relay`, ... | Human and hub routing hint |
| `firmware_id` | short hash/string | Running image id | Git sha or build id |

### 3.1 Static does not mean compile-time only

`board_family` may be compile-time. `mac` is not. Both still belong here if
they do not change during one boot cycle.

## 4. RuntimeCapability

These fields answer: *what can this node truthfully do right now?*

| Field | Type idea | Meaning | Why runtime |
| --- | --- | --- | --- |
| `mode` | enum | Current state-machine mode | Changes with transitions |
| `capabilities_now` | list/bitset | Actions currently available | Must shrink/expand with mode |
| `peripherals_active` | list/bitset | Peripherals currently powered/owned | Drives exclusivity truth |
| `gpio_owned` | compact list/bitset | Pins currently committed | Optional on tiny links, but canonical in card |
| `a2a_ready` | bool | Can receive/respond to peer messages now | May be false during bring-up or brownout |
| `sampling_state` | enum | idle / warming / sampling / blocked | Useful for sensor nodes |
| `degrade_flags` | bitset | e.g. `camera_off`, `psram_low`, `wifi_unavailable` | Makes graceful degrade explicit |

### 4.1 Capability honesty

A capability may appear in `sensor_inventory` statically but be absent from
`capabilities_now` dynamically.

Example:

- ESP32-CAM physically has `camera_ov2640`
- camera init failed this boot
- card must keep camera in static inventory, but remove capture from
  `capabilities_now` and add an appropriate degrade or error signal

## 5. Health

These fields help peers decide whether a node is fresh, alive, and stable.

| Field | Type idea | Meaning | Notes |
| --- | --- | --- | --- |
| `boot_epoch` | `u64`/token | Reset-boundary identity | Must differ across fresh boot boundaries |
| `uptime_ms` | `u64` | Monotonic uptime for this boot | Never wall clock |
| `last_peer_seen_ms` | `u64` or optional duration | Time since last peer contact on monotonic axis | Optional until transport exists |
| `free_internal_bytes` | `u32` | Free internal RAM | Separate from PSRAM |
| `free_psram_bytes` | `u32` | Free PSRAM | 0 if absent |
| `last_error` | enum/string/optional | Most recent notable failure | Compact, not a full log |
| `error_count` | `u32` | Count since boot | Helps detect flapping |
| `health_flags` | bitset | brownout, hot, low_mem, transport_down, ... | Small truthful summary |

## 6. Minimum card for early phases

Before real transport exists, the minimum serial-emitted card should still
contain enough truth for the hub to ingest later.

Required minimum:

- `schema_version`
- `node_kind`
- `board_family`
- `chip_family`
- `mac`
- `firmware_role`
- `firmware_id`
- `mode`
- `capabilities_now`
- `boot_epoch`
- `uptime_ms`
- `free_internal_bytes`
- `free_psram_bytes`

## 7. Edge ↔ Hub contract

`homeagent-config` should be able to ingest this card without knowing board
quirks.

The hub-facing minimum assumptions are:

1. `mac` + `board_family` + `firmware_role` are enough to form a companion
   registry key.
2. `boot_epoch` tells the hub whether this is the same node instance or a new
   one.
3. `capabilities_now` tells the hub what requests are currently worth routing.
4. `health_flags` and memory fields tell the hub whether to mirror the node as
   healthy, degraded, or unavailable.

## 8. Deliberate exclusions for now

Not in the first card shape unless a real need appears:

- full GPIO map dump
- transport-specific fields
- nested verbose telemetry histories
- wall-clock timestamps
- calibration blobs
- secrets, keys, or signatures

## 9. Open questions

1. Should `gpio_owned` be mandatory in the canonical card, or recoverable from
   `mode` on tiny transports?
2. Should `transport_hints` live in StaticProfile or be split into static
   support vs runtime availability?
3. Should `last_error` be a fixed enum from day one, or a short string during
   bring-up?
4. How should the hub expose multiple edge cards as one confederated public
   card upstream?
