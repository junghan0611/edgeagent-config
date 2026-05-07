"""Host-only fake edge — the seat the future Zig core will occupy.

This file implements the six-stage conveyor from ARCHITECTURE.md §4 in
the smallest honest way:

    poll low-level events
      → detector  (raw → meaningful events)
      → checkTimeouts (pure)
      → transition (pure)
      → view derivation (pure: NodeCard, ...)
      → I/O dispatch

Discipline preview (issue #1, INVARIANTS §14 candidate):

    transition() does NOT name peripherals.
    It reads `capabilities_now` bits and event kinds only.
    "camera", "speaker", "mic", "pir" never appear in transition().

That is enforced by the test in master.py (a static grep). When the
real Zig core lands, this property is what we are protecting.
"""

from __future__ import annotations

import os
import sys
import time
from dataclasses import dataclass, field, replace

import envelope as e

# --------------------------------------------------------------------------- #
# Static profile — boot-stable. Filled once at boot, immutable thereafter.
# --------------------------------------------------------------------------- #

STATIC_PROFILE = e.NodeCard(
    schema_version=e.SCHEMA_VERSION,
    node_kind="edge",
    board_family="host-sim",          # this is a simulated board
    chip_family="host",
    mac=bytes.fromhex("020000000001"),  # locally-administered, simulated
    firmware_role="observer",
    firmware_id="fake-edge-0.0.1",
    mode="idle",
    capabilities_now=[],              # filled at boot from the bit-set below
    peripherals_active=[],
    degrade_flags=[],
    a2a_ready=True,
    boot_epoch=0,
    uptime_ms=0,
    free_internal_bytes=0,
    free_psram_bytes=0,
    last_error=None,
    error_count=0,
    health_flags=[],
    skills=[
        e.NodeSkill(
            id="who_are_you",
            name="Self-introduction",
            description="Return the current NodeCard.",
            tags=["introspect"],
            examples=["who_are_you"],
        ),
        e.NodeSkill(
            id="what_can_you_do",
            name="Capability list",
            description="Return the currently advertised capability bits.",
            tags=["introspect"],
            examples=["what_can_you_do"],
        ),
        e.NodeSkill(
            id="read_health",
            name="Health snapshot",
            description="Return boot_epoch, uptime_ms, and free RAM.",
            tags=["introspect"],
            examples=["read_health"],
        ),
        e.NodeSkill(
            id="do_x",
            name="Named action",
            description="Run a small named action and ack. Today only 'ping'.",
            tags=["action"],
            examples=["do_x:ping"],
        ),
    ],
)

# Capability bits (small, stable enum). The transition function reads
# membership in this set; it does not know which peripheral each bit
# corresponds to. Mapping bit → peripheral lives at the board layer.
CAP_INTROSPECT = "introspect"
CAP_PING = "ping"


# --------------------------------------------------------------------------- #
# Mutable state — owned in exactly one place (INVARIANTS §4).
# --------------------------------------------------------------------------- #


@dataclass
class State:
    mode: str = "idle"
    mode_enter_ms: int = 0
    boot_epoch: int = 1
    boot_ms: int = 0  # monotonic ms at boot, for uptime_ms
    seq: int = 0
    last_peer: str = "?"
    capabilities_now: tuple[str, ...] = (CAP_INTROSPECT, CAP_PING)
    peripherals_active: tuple[str, ...] = ()  # nothing physical here
    degrade_flags: tuple[str, ...] = ()


# --------------------------------------------------------------------------- #
# Stage 4 — pure transition.
# --------------------------------------------------------------------------- #
#
# DISCIPLINE: this function must not mention peripheral names.
# It reads capability bits and event kinds. That is all.


def transition(
    state: State,
    env: e.Envelope,
    now_ms: int,
) -> tuple[State, list[e.Envelope]]:
    """Pure: (state, event, now_ms) → (next_state, outputs)."""
    outs: list[e.Envelope] = []
    next_state = state

    if env.kind == e.Kind.QUERY:
        body = env.body or {}
        qtype = body.get("type")

        if qtype == e.QueryType.WHO_ARE_YOU.value:
            outs.append(_make_card_reply(state, env, now_ms))

        elif qtype == e.QueryType.WHAT_CAN_YOU_DO.value:
            outs.append(_make_capability_reply(state, env, now_ms))

        elif qtype == e.QueryType.READ_HEALTH.value:
            outs.append(_make_health_reply(state, env, now_ms))

        elif qtype == e.QueryType.DO_X.value:
            action = body.get("action", "")
            if action == "ping" and CAP_PING in state.capabilities_now:
                outs.append(
                    _make_ack(state, env, now_ms, e.AckOutcome.COMPLETED, "pong")
                )
            else:
                outs.append(
                    _make_ack(
                        state,
                        env,
                        now_ms,
                        e.AckOutcome.REJECTED,
                        f"capability not advertised: {action!r}",
                    )
                )

        else:
            outs.append(
                _make_ack(state, env, now_ms, e.AckOutcome.REJECTED, "unknown query")
            )

    elif env.kind == e.Kind.EVENT:
        # No event handlers wired in Phase 4.5 yet. Ack and move on.
        outs.append(_make_ack(state, env, now_ms, e.AckOutcome.ACCEPTED, ""))

    else:
        outs.append(
            _make_ack(state, env, now_ms, e.AckOutcome.REJECTED, "unsupported kind")
        )

    next_state = replace(next_state, last_peer=env.from_)
    return next_state, outs


# --------------------------------------------------------------------------- #
# Stage 5 — view derivation. Pure functions of (state, time).
# --------------------------------------------------------------------------- #


def build_node_card(state: State, now_ms: int) -> e.NodeCard:
    """Build the canonical NodeCard from current state + time + StaticProfile.

    This is the "card builder" called out in INVARIANTS §9 and PROFILE §1.
    The board never serializes itself; the core composes the card.
    """
    card = replace(
        STATIC_PROFILE,
        mode=state.mode,
        capabilities_now=list(state.capabilities_now),
        peripherals_active=list(state.peripherals_active),
        degrade_flags=list(state.degrade_flags),
        boot_epoch=state.boot_epoch,
        uptime_ms=now_ms - state.boot_ms,
        free_internal_bytes=_free_internal_bytes(),
        free_psram_bytes=0,
    )
    return card


def _free_internal_bytes() -> int:
    """Sim only — host has no fixed budget. Report a stable lie."""
    return 256 * 1024


# --------------------------------------------------------------------------- #
# Reply builders (still pure of I/O).
# --------------------------------------------------------------------------- #


def _make_envelope(
    state: State,
    src: e.Envelope,
    now_ms: int,
    kind: e.Kind,
    body,
) -> e.Envelope:
    return e.Envelope(
        v=e.SCHEMA_VERSION,
        kind=kind,
        from_=_node_id(),
        to=src.from_,
        seq=state.seq,
        boot_epoch=state.boot_epoch,
        uptime_ms=now_ms - state.boot_ms,
        body=body,
    )


def _make_card_reply(state: State, src: e.Envelope, now_ms: int) -> e.Envelope:
    card = build_node_card(state, now_ms)
    # Send the full dict-shape body so the wire matches PROFILE.md.
    body = {
        "schema_version": card.schema_version,
        "node_kind": card.node_kind,
        "board_family": card.board_family,
        "chip_family": card.chip_family,
        "mac": card.mac,
        "firmware_role": card.firmware_role,
        "firmware_id": card.firmware_id,
        "mode": card.mode,
        "capabilities_now": card.capabilities_now,
        "peripherals_active": card.peripherals_active,
        "degrade_flags": card.degrade_flags,
        "a2a_ready": card.a2a_ready,
        "boot_epoch": card.boot_epoch,
        "uptime_ms": card.uptime_ms,
        "free_internal_bytes": card.free_internal_bytes,
        "free_psram_bytes": card.free_psram_bytes,
        "last_error": card.last_error,
        "error_count": card.error_count,
        "health_flags": card.health_flags,
        "skills": [
            {
                "id": s.id,
                "name": s.name,
                "description": s.description,
                "tags": s.tags,
                "examples": s.examples,
            }
            for s in card.skills
        ],
    }
    return _make_envelope(state, src, now_ms, e.Kind.CARD, body)


def _make_capability_reply(state: State, src: e.Envelope, now_ms: int) -> e.Envelope:
    body = {
        "capabilities_now": list(state.capabilities_now),
        "peripherals_active": list(state.peripherals_active),
        "degrade_flags": list(state.degrade_flags),
    }
    return _make_envelope(state, src, now_ms, e.Kind.ACK, body)


def _make_health_reply(state: State, src: e.Envelope, now_ms: int) -> e.Envelope:
    body = {
        "boot_epoch": state.boot_epoch,
        "uptime_ms": now_ms - state.boot_ms,
        "free_internal_bytes": _free_internal_bytes(),
        "free_psram_bytes": 0,
        "health_flags": [],
    }
    return _make_envelope(state, src, now_ms, e.Kind.ACK, body)


def _make_ack(
    state: State,
    src: e.Envelope,
    now_ms: int,
    outcome: e.AckOutcome,
    detail: str,
) -> e.Envelope:
    body = {
        "outcome": outcome.value,
        "ref_seq": src.seq,
        "detail": detail,
    }
    return _make_envelope(state, src, now_ms, e.Kind.ACK, body)


def _node_id() -> str:
    """Compact routing handle (ENVELOPE.md §4.1: 'from is the routing handle')."""
    return "edge:" + STATIC_PROFILE.mac.hex()


# --------------------------------------------------------------------------- #
# I/O dispatch — the only stage that touches the world.
# --------------------------------------------------------------------------- #


def now_ms() -> int:
    return time.monotonic_ns() // 1_000_000


def main() -> int:
    state = State(
        mode="idle",
        mode_enter_ms=now_ms(),
        boot_epoch=int(os.environ.get("FAKE_EDGE_BOOT_EPOCH", "1")),
        boot_ms=now_ms(),
        seq=0,
    )

    stdin = sys.stdin.buffer
    stdout = sys.stdout.buffer
    log = sys.stderr

    print(
        f"[fake_edge] booted boot_epoch={state.boot_epoch} "
        f"capabilities_now={list(state.capabilities_now)}",
        file=log,
        flush=True,
    )

    while True:
        try:
            env = e.read_frame(stdin)
        except EOFError:
            break
        if env is None:
            break

        # Stage 1+2 (poll + detector): the inbound envelope IS the event.
        # In the future Zig core, raw IO goes through a detector that lifts
        # bytes into Events. Here, the wire already speaks Events.

        # Stage 3 (checkTimeouts): no timed transitions in Phase 4.5 yet.

        # Stage 4 (pure transition).
        state = state.__class__(**{**state.__dict__, "seq": state.seq + 1})
        new_state, outs = transition(state, env, now_ms())
        state = new_state

        # Stage 6 (I/O dispatch).
        for out in outs:
            e.write_frame(stdout, out)

    print("[fake_edge] stdin closed; shutting down.", file=log, flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
