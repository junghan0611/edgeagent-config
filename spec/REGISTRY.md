# Companion Registry

This file defines the registry shape that lets a hub or another family member
track edge nodes without mutating their original contract.

The registry does not replace the card. It indexes cards across time.

## 1. Purpose

The registry exists to answer four questions:

1. **Who is this node across boots?**
2. **Which specific instance of that node am I talking to right now?**
3. **What was the last truthful card/envelope I received?**
4. **What derived view am I allowed to project without overwriting the raw one?**

In short:

- registry owns identity
- ingest preserves truth
- mirror derives view
- federation exports projection

## 2. Identity split

The registry must separate persistent identity from instance identity.

### 2.1 Persistent identity

A node's persistent identity survives reboot boundaries.

```text
persistent_id = mac + board_family + firmware_role
```

Why:

- `mac` alone is too thin for the project vocabulary
- `board_family` matters for profile and capability interpretation
- `firmware_role` matters for routing and human meaning

This is the registry key for the enduring companion.

### 2.2 Instance identity

A node instance is one persistent companion in one boot epoch.

```text
instance_id = persistent_id + boot_epoch
```

Why:

- same physical node, different boot cycle = different instance
- peers must not silently treat a rebooted node as a continuation

## 3. Registry layers

The registry should keep three layers distinct.

### 3.1 Companion record (persistent layer)

One record per enduring node.

Suggested shape:

```text
CompanionRecord {
  persistent_id
  first_seen_at
  last_seen_at
  latest_instance_id
  board_family
  chip_family
  mac
  firmware_role
  status_summary        ; healthy / degraded / unavailable / unknown
  latest_card_ref       ; pointer to last accepted raw card/envelope
  mirror_view_ref       ; pointer to derived operational summary
  represented_by        ; optional hub or family member id
}
```

### 3.2 Instance record (boot layer)

One record per observed boot epoch.

Suggested shape:

```text
InstanceRecord {
  instance_id
  persistent_id
  boot_epoch
  firmware_id
  first_seen_at
  last_seen_at
  last_uptime_ms
  last_seq
  latest_envelope_ref
  instance_status       ; live / stale / replaced / unknown
}
```

### 3.3 Ingest record (truth layer)

One record per received canonical envelope.

Suggested shape:

```text
IngestRecord {
  ingest_id
  received_at
  carrier                ; serial / esp-now / mqtt / ...
  carrier_metadata_ref   ; RSSI, topic, port, etc. outside canonical envelope
  raw_cbor
  decoded_envelope
  validation_result
  persistent_id
  instance_id
}
```

This is the layer that preserves truth.

## 4. Ownership boundaries

### Registry owns identity

The registry decides how to index enduring companions and boot instances. It
must not rewrite the edge node's canonical envelope to do so.

### Ingest preserves truth

The ingest path stores the exact raw payload plus a decoded view. If decoding or
mapping improves later, the system must still be able to re-read the original
bytes.

### Mirror derives view

A mirror is a convenience summary for routing, dashboards, or health checks.
It is derived from raw truth; it does not replace it.

### Federation exports projection

A public or upstream projection may summarize many nodes through the hub, but it
must never erase which raw edge records it came from.

## 5. Freshness and replacement rules

The registry needs explicit decisions when new envelopes arrive.

### 5.1 Same persistent_id, same boot_epoch

Interpretation:
- same node
- same boot instance
- update the instance's `last_seen_at`, `last_uptime_ms`, `last_seq`

### 5.2 Same persistent_id, different boot_epoch

Interpretation:
- same enduring companion
- new boot instance
- close or mark old instance as replaced/stale
- create a new `InstanceRecord`

### 5.3 Different persistent_id, same MAC

Interpretation:
- likely profile change, board reprovision, or contract drift
- do not silently merge
- require an explicit policy decision or quarantine state

### 5.4 Non-monotonic sequence or uptime within same instance

Interpretation:
- possible replay, decode error, reset ambiguity, or transport duplication
- preserve raw ingest record first
- mark validation warning
- do not destroy prior accepted state

## 6. Validation posture

Validation should be strict enough to protect trust, but should preserve raw
bytes even on failure.

Suggested validation outputs:

- `accepted`
- `accepted_with_warning`
- `rejected_schema`
- `rejected_identity_conflict`
- `rejected_decode_failure`

Even rejected envelopes may remain stored as raw ingest evidence.

## 7. Minimal registry fields needed by the hub

A hub does not need the whole card in every index.

Minimum companion index:

- `persistent_id`
- `latest_instance_id`
- `board_family`
- `firmware_role`
- `status_summary`
- `last_seen_at`

Minimum instance index:

- `instance_id`
- `boot_epoch`
- `firmware_id`
- `last_uptime_ms`
- `last_seq`
- `instance_status`

## 8. What the registry must never do

- overwrite `raw_cbor` with a re-encoded payload
- merge two different boot epochs into one instance
- collapse mirror metadata into the canonical envelope
- let a federated public view replace the raw edge card
- assume MAC alone is the whole identity forever

## 9. Open questions

1. Should `firmware_role` remain part of persistent identity forever, or become
   a mutable classification later?
2. If a board is reflashed into a different role intentionally, is that a new
   companion or the same companion with a new declared role?
3. Should the registry maintain a separate quarantine table for identity
   conflicts?
4. What exact fields should be indexed for fast routing without re-decoding
   every raw envelope?
