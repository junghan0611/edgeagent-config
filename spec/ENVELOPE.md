# A2A Envelope

This file defines the canonical envelope that carries edge cards, events, and
acks across transports. The transport may change. The bytes that express the
contract may not.

## 1. Scope

Layer split:

- **Layer 3 (this file)** — one canonical envelope shape and one canonical
  encoding.
- **Layer 4 (transport)** — ESP-NOW, MQTT, BLE, CoAP, serial framing,
  fragmentation, retransmission.

If a transport cannot carry the envelope in one frame, Layer 4 fragments it.
Layer 3 does not delete fields to make a carrier happy.

## 2. Canonical encoding decision

**Canonical encoding: CBOR.**

Why CBOR, not JSON:

- binary size matters on ESP-NOW-class transports
- fixed small integers / short keys stay compact
- host tools can still decode it easily
- one binary form reduces the temptation to let each transport improvise

JSON may be used by tooling only as a *derived debug view*, never as the
canonical on-wire grammar.

## 3. Envelope families

The edge side needs only a few top-level message kinds at first:

| Kind | Purpose |
| --- | --- |
| `card` | Self-description |
| `query` | Ask a node for card, capability, or specific data |
| `event` | Inbound stimulus routed into the core |
| `ack` | Delivery / execution acknowledgement |

This is intentionally smaller than a full desktop A2A stack.

## 4. Canonical envelope shape

```text
Envelope {
  v              ; schema version
  kind           ; card | query | event | ack
  from           ; sender node id
  to             ; destination node id or broadcast token
  seq            ; sender-local sequence number
  boot_epoch     ; sender boot identity
  uptime_ms      ; sender monotonic uptime for this boot
  body           ; kind-specific payload
}
```

### 4.1 Field intent

| Field | Meaning | Notes |
| --- | --- | --- |
| `v` | Envelope schema version | Starts at 1 |
| `kind` | Top-level message family | Small enum |
| `from` | Sender identity token | Initially MAC-derived or registry-derived |
| `to` | Recipient token or broadcast | Transport-independent |
| `seq` | Sender-local sequence | Helps dedupe / ordering hints |
| `boot_epoch` | Sender boot identity | Required for freshness |
| `uptime_ms` | Sender monotonic uptime | Never wall clock |
| `body` | Payload for the kind | See below |

`from` is not the whole identity story; it is the routing handle. The full
identity still lives in the `card` body.

## 5. Body shapes

### 5.1 `card`

```text
body = NodeCard
```

The canonical card shape lives in [PROFILE.md](PROFILE.md) (same folder).

### 5.2 `query`

Minimal early query forms:

| Query type | Meaning |
| --- | --- |
| `who_are_you` | Request current NodeCard |
| `what_can_you_do` | Request current capability subset |
| `read_health` | Request current health subset |
| `do_x` | Ask for a named action that becomes an Event |

For early phases, `do_x` should stay small and symbolic. It is not a free-form
RPC tunnel.

### 5.3 `event`

`event` carries a state-machine stimulus. Even if it arrived over radio, the
core should see it as an Event, not as a transport exception.

Examples:

- `peer_card_seen`
- `peer_query_received`
- `capture_requested`
- `actuator_command_received`

### 5.4 `ack`

Acknowledge that something was:

- received
- accepted into the core
- rejected
- completed
- degraded

The ack is small. It does not duplicate the whole original message.

## 6. Size budget

The contract should be designed with a harsh carrier in mind even before that
carrier is implemented.

Working budget:

- **Target:** one compact card fits in **<= 192 bytes encoded CBOR**
- **Hard warning zone:** 193–240 bytes
- **Over MTU risk:** > 240 bytes on ESP-NOW-class links

Why 192 bytes:

- leaves room for transport framing / metadata
- leaves headroom for future fields without immediate fragmentation
- forces discipline in card shape

Design implication:

- compact enums over verbose strings on wire
- optional fields omitted when absent
- inventories represented as bitsets where possible
- debug-rich expansion belongs in host tooling, not in the radio payload

## 7. Transport responsibilities

Layer 4 may do:

- frame delimiting
- fragmentation / reassembly
- retries
- transport-specific addressing adaptation
- RSSI / topic / BLE metadata outside the canonical envelope

Layer 4 may not do:

- remove canonical fields
- add transport-only semantic fields into the envelope
- switch encoding per carrier
- reinterpret wall clock as uptime or vice versa

## 8. Edge ↔ Hub bridge posture

`homeagent-config` is expected to act as representative / bridge /
confederation.

That means:

1. ingest canonical edge envelopes unchanged
2. preserve original `from`, `boot_epoch`, and `seq` when mirroring
3. add bridge metadata outside the canonical envelope
4. expose a richer upstream view without mutating the original edge contract

The hub may *summarize* or *federate* many edge cards, but it should still be
able to recover the original edge envelope losslessly.

## 9. Serial is still a transport

Before radio exists, serial output is not a special case. It is simply the
first Layer 4 carrier.

That is useful because:

- the first firmware can emit real envelopes immediately
- the host parser can validate round trips before ESP-NOW/MQTT exists
- the same parser can later ingest radio-delivered envelopes

## 10. Open questions

1. What is the exact compact node-id form for `from` / `to` before a larger
   registry exists?
2. Should `query` be a single small enum body first, with parameters added only
   after a real need appears?
3. Is 192 bytes the right target for the first card, or should the project aim
   below 160?
4. When the hub federates many edge nodes, what should be preserved as raw
   canonical data and what should be lifted into a hub-level summary?
