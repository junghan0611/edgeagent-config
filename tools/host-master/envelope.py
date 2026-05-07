"""Canonical envelope encoding for the edge agent.

This is the host-only Python mirror of the contract defined in
spec/ENVELOPE.md. It exists so that fake_edge.py and master.py share
exactly one wire grammar today, before the Zig core exists.

Decisions, traceable to spec:

- CBOR is the canonical encoding (ENVELOPE.md §2). JSON is debug only.
- The envelope has 8 top-level fields (ENVELOPE.md §4): v, kind, from,
  to, seq, boot_epoch, uptime_ms, body.
- Four kinds (ENVELOPE.md §3): card, query, event, ack.
- This module never imports a2a SDKs (issue #1). It is small on purpose.

Naming-only borrow from a2a-samples/helloworld: the human-facing fields
of a NodeSkill (id / name / description / tags / examples) follow the
same shape so the future hub can promote them into AgentCard.skills[]
with zero translation. See issue #1.
"""

from __future__ import annotations

import enum
from dataclasses import dataclass, field, asdict
from typing import Any

import cbor2  # nix devShell: python3Packages.cbor2

SCHEMA_VERSION = 1


# --------------------------------------------------------------------------- #
# Envelope kinds
# --------------------------------------------------------------------------- #


class Kind(str, enum.Enum):
    """ENVELOPE.md §3 — the only four top-level message families."""

    CARD = "card"
    QUERY = "query"
    EVENT = "event"
    ACK = "ack"


# --------------------------------------------------------------------------- #
# Query types (ENVELOPE.md §5.2)
# --------------------------------------------------------------------------- #


class QueryType(str, enum.Enum):
    WHO_ARE_YOU = "who_are_you"
    WHAT_CAN_YOU_DO = "what_can_you_do"
    READ_HEALTH = "read_health"
    DO_X = "do_x"  # parameterized via body.action


# --------------------------------------------------------------------------- #
# Ack outcomes (ENVELOPE.md §5.4)
# --------------------------------------------------------------------------- #


class AckOutcome(str, enum.Enum):
    ACCEPTED = "accepted"
    REJECTED = "rejected"
    COMPLETED = "completed"
    DEGRADED = "degraded"


# --------------------------------------------------------------------------- #
# NodeCard (PROFILE.md §6 minimum)
# --------------------------------------------------------------------------- #


@dataclass
class NodeSkill:
    """One human-facing capability description.

    Naming follows a2a-samples AgentSkill so the hub layer can promote
    it later (issue #1). This shape never goes on the ESP-NOW wire as-is
    — the small wire form is `capabilities_now` bitmask. NodeSkill is
    only carried in `who_are_you`-style introspection responses.
    """

    id: str
    name: str
    description: str
    tags: list[str] = field(default_factory=list)
    examples: list[str] = field(default_factory=list)


@dataclass
class NodeCard:
    """The smallest truthful sentence a node can say about itself.

    Mirrors PROFILE.md §6. Field names are stable: any rename here is a
    contract change.
    """

    # StaticProfile (boot-stable)
    schema_version: int
    node_kind: str  # "edge"
    board_family: str
    chip_family: str
    mac: bytes
    firmware_role: str
    firmware_id: str

    # RuntimeCapability
    mode: str
    capabilities_now: list[str]
    peripherals_active: list[str] = field(default_factory=list)
    degrade_flags: list[str] = field(default_factory=list)
    a2a_ready: bool = True

    # Health
    boot_epoch: int = 0
    uptime_ms: int = 0
    free_internal_bytes: int = 0
    free_psram_bytes: int = 0
    last_error: str | None = None
    error_count: int = 0
    health_flags: list[str] = field(default_factory=list)

    # Human-facing skill catalog (naming borrowed from a2a — see module
    # docstring). Optional in tight wire forms.
    skills: list[NodeSkill] = field(default_factory=list)


# --------------------------------------------------------------------------- #
# Envelope (ENVELOPE.md §4)
# --------------------------------------------------------------------------- #


@dataclass
class Envelope:
    v: int
    kind: Kind
    from_: str  # "from" is reserved in Python; serialize back to "from"
    to: str
    seq: int
    boot_epoch: int
    uptime_ms: int
    body: Any  # kind-specific


# --------------------------------------------------------------------------- #
# CBOR encode / decode
# --------------------------------------------------------------------------- #


def _to_dict(obj: Any) -> Any:
    """Recursively convert dataclasses + enums to plain CBOR-friendly types."""
    if isinstance(obj, Envelope):
        return {
            "v": obj.v,
            "kind": obj.kind.value if isinstance(obj.kind, enum.Enum) else obj.kind,
            "from": obj.from_,
            "to": obj.to,
            "seq": obj.seq,
            "boot_epoch": obj.boot_epoch,
            "uptime_ms": obj.uptime_ms,
            "body": _to_dict(obj.body),
        }
    if isinstance(obj, NodeCard):
        d = asdict(obj)
        # asdict turns nested NodeSkill into dicts already; mac stays bytes.
        return d
    if isinstance(obj, NodeSkill):
        return asdict(obj)
    if isinstance(obj, enum.Enum):
        return obj.value
    if isinstance(obj, dict):
        return {k: _to_dict(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_to_dict(v) for v in obj]
    return obj


def encode(env: Envelope) -> bytes:
    """Serialize an Envelope to canonical CBOR bytes."""
    return cbor2.dumps(_to_dict(env))


def decode(buf: bytes) -> Envelope:
    """Deserialize CBOR bytes back into an Envelope.

    Body is left as a plain dict / primitive; callers that expect a
    NodeCard re-hydrate via `nodecard_from_body()`.
    """
    raw = cbor2.loads(buf)
    if not isinstance(raw, dict):
        raise ValueError(f"envelope must decode to dict, got {type(raw).__name__}")
    return Envelope(
        v=int(raw["v"]),
        kind=Kind(raw["kind"]),
        from_=str(raw["from"]),
        to=str(raw["to"]),
        seq=int(raw["seq"]),
        boot_epoch=int(raw["boot_epoch"]),
        uptime_ms=int(raw["uptime_ms"]),
        body=raw["body"],
    )


def nodecard_from_body(body: dict) -> NodeCard:
    """Re-hydrate a NodeCard from a decoded envelope body."""
    skills = [NodeSkill(**s) for s in body.get("skills", [])]
    fields_in = {**body}
    fields_in["skills"] = skills
    return NodeCard(**fields_in)


# --------------------------------------------------------------------------- #
# JSON debug view (ENVELOPE.md §2 — debug-only, never canonical)
# --------------------------------------------------------------------------- #


def to_debug_dict(env: Envelope) -> dict:
    """Human-readable view. Bytes (mac) are rendered as hex."""

    def _humanize(o: Any) -> Any:
        if isinstance(o, bytes):
            return ":".join(f"{b:02x}" for b in o)
        if isinstance(o, dict):
            return {k: _humanize(v) for k, v in o.items()}
        if isinstance(o, list):
            return [_humanize(v) for v in o]
        return o

    return _humanize(_to_dict(env))


# --------------------------------------------------------------------------- #
# Length-prefixed framing for stdin/stdout
# --------------------------------------------------------------------------- #
#
# Why: stdin is a byte stream, not a message stream. CBOR is self-
# delimiting in principle, but a 4-byte big-endian length prefix
# survives partial reads cleanly and matches what a future serial
# Layer 4 will likely need anyway. This is *transport framing*, not
# part of the canonical envelope (ENVELOPE.md §7).


def write_frame(stream, env: Envelope) -> None:
    payload = encode(env)
    stream.write(len(payload).to_bytes(4, "big"))
    stream.write(payload)
    stream.flush()


def read_frame(stream) -> Envelope | None:
    header = stream.read(4)
    if not header:
        return None
    if len(header) != 4:
        raise EOFError(f"short header: {len(header)} bytes")
    n = int.from_bytes(header, "big")
    payload = stream.read(n)
    if len(payload) != n:
        raise EOFError(f"short payload: got {len(payload)} of {n} bytes")
    return decode(payload)
