"""Host master — throws envelopes at fake_edge.py and prints replies.

This is the pre-firmware master. It does what a Claude / pi / human
might do at a terminal: introduce yourself, list your skills, report
your health, run a tiny named action. No board required.

When the real Zig core arrives, only the subprocess target changes.
The four queries below stay the same.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import textwrap
from pathlib import Path

import envelope as e

HERE = Path(__file__).resolve().parent
FAKE_EDGE = HERE / "fake_edge.py"

MASTER_ID = "host:master"


# --------------------------------------------------------------------------- #
# Pretty printing
# --------------------------------------------------------------------------- #


def _hr(title: str) -> None:
    print(f"\n── {title} " + "─" * (60 - len(title)))


def _show(env: e.Envelope) -> None:
    d = e.to_debug_dict(env)
    print(json.dumps(d, indent=2, ensure_ascii=False))


# --------------------------------------------------------------------------- #
# Round-trip helper
# --------------------------------------------------------------------------- #


def query(
    proc: subprocess.Popen,
    seq: int,
    qtype: e.QueryType,
    action: str | None = None,
) -> e.Envelope:
    body = {"type": qtype.value}
    if action is not None:
        body["action"] = action

    env = e.Envelope(
        v=e.SCHEMA_VERSION,
        kind=e.Kind.QUERY,
        from_=MASTER_ID,
        to="edge:*",
        seq=seq,
        boot_epoch=0,  # master has no epoch
        uptime_ms=0,
        body=body,
    )

    e.write_frame(proc.stdin, env)
    reply = e.read_frame(proc.stdout)
    if reply is None:
        raise RuntimeError("fake_edge closed stdout unexpectedly")
    return reply


# --------------------------------------------------------------------------- #
# Discipline test — transition() must not name peripherals.
#
# This is the invariant §14 candidate from issue #1, demonstrated as a
# static check rather than a runtime rule. If a future contributor adds
# `if event == camera_request` into transition(), this catches it.
# --------------------------------------------------------------------------- #


_FORBIDDEN_PERIPHERAL_NAMES = (
    "camera",
    "speaker",
    "microphone",
    "mic",
    "pir",
    "ov2640",
    "i2s",
    "led",
    "gpio",
)


def _check_transition_discipline() -> None:
    src = (HERE / "fake_edge.py").read_text(encoding="utf-8")
    # Find the start of `def transition(` and walk forward until the
    # next top-level `def ` (or EOF). This survives multi-line
    # signatures, which a single-line regex does not.
    start = src.find("\ndef transition(")
    if start < 0:
        raise AssertionError("could not locate transition() in fake_edge.py")
    rest = src[start + 1 :]  # drop the leading newline
    next_def = re.search(r"^def ", rest[len("def transition") :], re.MULTILINE)
    end = (next_def.start() + len("def transition")) if next_def else len(rest)
    body = rest[:end]
    # Strip comments — invariant talks about runtime semantics, not docs.
    body_no_comments = re.sub(r"#[^\n]*", "", body)
    hits = [
        word for word in _FORBIDDEN_PERIPHERAL_NAMES if word in body_no_comments.lower()
    ]
    if hits:
        raise AssertionError(
            f"transition() mentions peripheral names {hits}. "
            "Per issue #1 invariant §14 candidate, the core reads capability "
            "bits and event kinds only. Move the peripheral-aware logic to "
            "the board layer."
        )


# --------------------------------------------------------------------------- #
# Main walk
# --------------------------------------------------------------------------- #


def main() -> int:
    _check_transition_discipline()
    print("[master] discipline check passed: transition() names no peripherals.")

    env = os.environ.copy()
    # Make sure fake_edge.py can import envelope.py without site-packages noise.
    env["PYTHONPATH"] = str(HERE) + os.pathsep + env.get("PYTHONPATH", "")

    proc = subprocess.Popen(
        [sys.executable, str(FAKE_EDGE)],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=sys.stderr,
        env=env,
    )

    try:
        if proc.stdin is None or proc.stdout is None:
            raise RuntimeError("subprocess pipes not open")

        _hr("1. who_are_you  →  card")
        reply = query(proc, seq=1, qtype=e.QueryType.WHO_ARE_YOU)
        assert reply.kind == e.Kind.CARD, f"expected card, got {reply.kind}"
        _show(reply)

        _hr("2. what_can_you_do  →  ack(capabilities)")
        reply = query(proc, seq=2, qtype=e.QueryType.WHAT_CAN_YOU_DO)
        assert reply.kind == e.Kind.ACK
        _show(reply)

        _hr("3. read_health  →  ack(health)")
        reply = query(proc, seq=3, qtype=e.QueryType.READ_HEALTH)
        assert reply.kind == e.Kind.ACK
        _show(reply)

        _hr("4. do_x=ping  →  ack(completed:pong)")
        reply = query(proc, seq=4, qtype=e.QueryType.DO_X, action="ping")
        assert reply.kind == e.Kind.ACK
        assert reply.body.get("outcome") == e.AckOutcome.COMPLETED.value
        _show(reply)

        _hr("5. do_x=fly  →  ack(rejected: not advertised)")
        reply = query(proc, seq=5, qtype=e.QueryType.DO_X, action="fly")
        assert reply.kind == e.Kind.ACK
        assert reply.body.get("outcome") == e.AckOutcome.REJECTED.value
        _show(reply)

        _hr("done")
        print(
            textwrap.dedent(
                """
                엣지가 살아났다.
                  · CBOR envelope round-trip: ok
                  · 4 query kinds answered: ok
                  · transition() peripheral-name discipline: ok
                  · advertised capability matches answered actions: ok

                Next seat for this code: a Zig core compiled for host, then
                for ESP32. The wire stays unchanged.
                """
            ).strip()
        )

    finally:
        if proc.stdin and not proc.stdin.closed:
            proc.stdin.close()
        proc.wait(timeout=5)

    return 0


if __name__ == "__main__":
    sys.exit(main())
