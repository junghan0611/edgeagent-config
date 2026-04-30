# Ingest Pipeline

This file defines how a family member receives a canonical edge envelope,
preserves it as truth, validates it, binds it into registry identity, and only
then derives mirror or federated views.

The ingest path is where transport noise ends and contract discipline begins.

## 1. Purpose

The ingest pipeline must guarantee four things:

1. raw truth is preserved before interpretation
2. validation is explicit and replayable
3. registry binding does not mutate the original envelope
4. mirror / federation are derived projections, never replacements

Short form:

- capture preserves bytes
- validation preserves meaning
- registry binds identity
- projection derives views

## 2. Pipeline stages

Canonical flow:

```text
carrier input
-> raw capture
-> decode
-> validate schema
-> bind identity
-> resolve registry freshness/replacement
-> derive mirror view
-> derive federated/public projection
```

Carrier input may be serial, ESP-NOW, MQTT, BLE, or another family transport.
The canonical envelope begins only after payload extraction.

## 3. IngestRecord

One ingest record corresponds to one received canonical envelope.

Suggested shape:

```text
IngestRecord {
  ingest_id
  persistent_id
  instance_id
  raw_cbor
  decoded_envelope
  validation_state
  validation_errors
  carrier
  carrier_metadata
  mirror_metadata
  received_monotonic_ms
  received_wallclock_ms
  mirror_ref
  federated_ref
}
```

### 3.1 Field intent

| Field | Meaning | Notes |
| --- | --- | --- |
| `ingest_id` | unique ingest event id | Local storage key |
| `persistent_id` | resolved enduring companion id | May be absent before identity bind succeeds |
| `instance_id` | resolved boot-instance id | Derived from persistent id + boot epoch |
| `raw_cbor` | exact original canonical bytes | Never overwritten |
| `decoded_envelope` | structured decoded form | Derived from `raw_cbor` |
| `validation_state` | current pipeline state | See §4 |
| `validation_errors` | accumulated warnings/errors | Structured list preferred |
| `carrier` | serial / esp-now / mqtt / ... | Transport provenance |
| `carrier_metadata` | framing / RSSI / topic / port / source path | Outside canonical envelope |
| `mirror_metadata` | local derived operational annotations | Outside canonical envelope |
| `received_monotonic_ms` | local monotonic receive time | For pipeline timing and ordering |
| `received_wallclock_ms` | local wallclock receive time | For logs / humans only |
| `mirror_ref` | pointer to derived mirror view | Optional |
| `federated_ref` | pointer to derived public/representative projection | Optional |

## 4. Validation state machine

Recommended states:

```text
received
-> decoded
-> schema_valid
-> identity_bound
-> mirrored
-> federated

Any stage may transition to:
rejected
```

### 4.1 State meanings

| State | Meaning |
| --- | --- |
| `received` | bytes captured successfully |
| `decoded` | canonical CBOR decoded into envelope structure |
| `schema_valid` | required fields and shapes accepted |
| `identity_bound` | persistent / instance identity resolved and registry-linked |
| `mirrored` | local mirror/operational view derived |
| `federated` | representative/public projection updated |
| `rejected` | pipeline stopped due to validation failure or conflict |

### 4.2 Rejection does not erase truth

Even a rejected record may preserve:

- `raw_cbor`
- `carrier_metadata`
- partial decode diagnostics
- validation errors

A bad record is still evidence.

## 5. Validation rules

### 5.1 Decode validation

Checks:

- payload is canonical CBOR
- top-level envelope keys exist
- `kind`, `from`, `seq`, `boot_epoch`, `uptime_ms`, `body` are decodable

Failure:
- `validation_state = rejected`
- include `rejected_decode_failure`
- keep `raw_cbor`

### 5.2 Schema validation

Checks:

- `v` supported
- `kind` known
- required fields present for the kind
- `uptime_ms` on monotonic meaning, not wall clock
- `body` shape matches `kind`

Failure:
- `validation_state = rejected`
- include `rejected_schema`

### 5.3 Identity binding

Checks:

- `persistent_id = mac + board_family + firmware_role`
- `instance_id = persistent_id + boot_epoch`
- registry conflict rules applied explicitly

Failure:
- `validation_state = rejected`
- include `rejected_identity_conflict`

## 6. Freshness and replacement resolution

The ingest path must apply registry rules, not invent new ones.

### 6.1 Same persistent_id, same boot_epoch

Interpretation:
- same enduring companion
- same boot instance
- update instance freshness and link ingest record to that instance

### 6.2 Same persistent_id, different boot_epoch

Interpretation:
- same enduring companion
- new boot instance
- old instance becomes stale/replaced per policy
- new ingest record binds to new instance

### 6.3 Same MAC, different persistent_id

Interpretation:
- role change, reprovisioning, board-profile drift, or conflict
- do not silently merge
- quarantine or explicit policy path recommended

## 7. Projection references

Derived views must reference truth, not replace it.

### 7.1 Mirror view

A mirror view is an operational summary for local automation, dashboards, or
routing.

Rules:

- mirror view references one or more `IngestRecord`s
- mirror view may add local summaries
- mirror view may not overwrite `decoded_envelope`
- mirror metadata stays outside canonical envelope

### 7.2 Federated/public representative view

A federated/public view is what the hub chooses to say upstream.

Rules:

- references mirror or raw ingest records explicitly
- may summarize many companions
- may hide local transport details
- must not claim to be the original edge envelope

## 8. Timestamps: local receive time vs remote node time

Do not confuse:

- `received_monotonic_ms` — local host monotonic time when ingest occurred
- `received_wallclock_ms` — local host wall clock for logs
- `decoded_envelope.uptime_ms` — remote node monotonic uptime for that boot

These are different axes, owned by different systems.

## 9. What ingest must never do

- overwrite `raw_cbor` with normalized or re-encoded bytes
- collapse `carrier_metadata` into the canonical envelope
- collapse `mirror_metadata` into the canonical envelope
- use a public projection as the source of truth for registry binding
- discard a rejected record before preserving raw evidence
- treat wall clock as a substitute for node uptime

## 10. Open questions

1. Should `validation_errors` be a flat list or stage-grouped structure?
2. Should `mirror_ref` and `federated_ref` be stored directly in each ingest
   record, or derived through reverse indexes?
3. What local monotonic clock source should the hub standardize on for
   `received_monotonic_ms`?
4. Should the quarantine path for identity conflicts be described here or in a
   future operations note?
