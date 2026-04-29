# edgeagent-config

> I am the Edge.

`edgeagent-config` is a public research shell for small A2A-capable edge agents.
It is intentionally documentation-first: no firmware template, no build system, no
runtime scaffold yet. The first artifact is the set of invariants that future Zig
edge nodes must not violate.

## Why this exists

`homeagent-config` is for Raspberry Pi 5 class home agents: Go, Node.js, Linux,
services, and orchestration.

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

A hub coordinates the home. An edge node is closer to the world. It may have two
sensors attached to its body. It observes, keeps state, and talks to peers.

## Design stance

The architecture is expected to be a state machine:

```text
Input Event -> pure transition(state, event) -> next state + output actions
```

Real I/O is outside the core. Timers are derived from state entry timestamps.
Communication is modeled as explicit events and outputs, not hidden callbacks.

The long-term design question is Sussman-like: how do we build software that can
remain flexible under changing requirements without becoming vague or unsafe?
For this repository, flexibility does not mean ad-hoc behavior. It means clear
interfaces, explicit time axes, replaceable I/O, testable transitions, and
small pieces that can be recomposed.

## Current scope

This repository currently contains only:

- `README.md` — purpose and direction
- `AGENTS.md` — working guide for agents and humans
- `docs/invariants.md` — non-negotiable design invariants

Code will come later, after the invariants are stable enough to deserve a
template.

## Non-goals for now

- No `src/` tree yet
- No `build.zig` yet
- No premature hardware abstraction layer
- No fake sample app just to look complete
- No dependency choices before the architecture has a reason

## First principles

1. Time is not a scalar.
2. State is owned by the node state machine.
3. I/O is an edge of the system, not the center.
4. A small node is still an agent.
5. Flexibility comes from explicit contracts, not from implicit behavior.
