# tools/host-master — Phase 4.5

A host-side toy that proves "엣지가 살아난다" without any ESP board.

## Why this exists

`fake_edge.py` is the **seat the future Zig core will occupy**. It runs
the same six-stage conveyor described in
[ARCHITECTURE.md §4](../../ARCHITECTURE.md), answers the same four
envelope kinds defined in [spec/ENVELOPE.md §3](../../spec/ENVELOPE.md),
and emits the same `NodeCard` shape from
[spec/PROFILE.md](../../spec/PROFILE.md).

`master.py` is the **host-side agent (you, or Claude)** that throws
envelopes at the edge and prints what comes back. It does not need to
be embedded — that decision is recorded in
[issue #1](https://github.com/junghan0611/edgeagent-config/issues/1).

When the real Zig core lands (Phase 2), `fake_edge.py` is replaced.
The wire stays the same.

## What you get today

- `envelope.py` — CBOR encode/decode for the 4 envelope kinds.
- `fake_edge.py` — a host-only edge that:
  - boots once, fills a `StaticProfile` (chip family, MAC, inventories),
  - runs a 100 ms self-inspect loop,
  - reads CBOR envelopes from stdin,
  - answers `who_are_you`, `what_can_you_do`, `read_health`, `do_x=ping`,
  - writes CBOR envelopes to stdout.
- `master.py` — spawns `fake_edge.py` as a subprocess and walks the
  four queries in order, pretty-printing each round trip.

## Run it

From repo root:

```sh
./run.sh hello-edge
```

Or inside the dev shell:

```sh
nix develop
python3 tools/host-master/master.py
```

## What this is not

- Not firmware. The Zig core is not here yet.
- Not a transport adapter. There is no serial, no ESP-NOW, no MQTT.
  The transport is stdin/stdout, by design — Phase 3 will swap it.
- Not an a2a server. We do not import any a2a SDK here. See
  [issue #1](https://github.com/junghan0611/edgeagent-config/issues/1).
- Not a place for peripheral drivers. The `transition()` function in
  `fake_edge.py` deliberately reads `capabilities_now` bits, not
  peripheral names like `camera` or `speaker` — this previews the
  invariant §14 candidate from issue #1.

## Replacing this with the real core

When Phase 2 lands, the layout is:

```
host:
  master.py                   ← unchanged
host (or device):
  zig core (state, transition, card builder)
                              ← replaces fake_edge.py
```

The wire bytes (CBOR envelope) are unchanged. If round-trip breaks,
the encoder/decoder asymmetry is in one place.
