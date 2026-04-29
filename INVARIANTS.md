# Edge Agent Invariants

These invariants are written before code on purpose. They are the design memory
of failures that should not be rediscovered in firmware.

## 1. Time is not a scalar

Every time value must declare its axis.

| Axis | Meaning | Examples | Rule |
| --- | --- | --- | --- |
| Wall clock | Human calendar time | logs, user-visible timestamps | May jump; never use for elapsed logic |
| Monotonic uptime | Non-decreasing process/system uptime | `CLOCK_MONOTONIC` | Use for elapsed time and timeouts |
| Wrapping tick | Fixed-width counter | SDK `u32` millisecond tick | Compare with wrapping arithmetic |
| Duration | Difference between two values on the same axis | elapsed ms/sec | Never mix axes |

Forbidden:

```zig
now_wall_ms - state_enter_monotonic_ms
now_uptime_ms - @as(u64, sdk_u32_tick)
```

Correct:

```zig
elapsedFromSameAxis(now_monotonic_ms, state_enter_monotonic_ms)
elapsedFromWrappingTick(sdk_last_tick, now_monotonic_ms)
```

## 2. Widen before multiplying time units

Platform-sized integers are not stable across targets.

On ARM32, `isize == i32`. This means a seconds-to-milliseconds conversion can
fail if multiplication happens before widening.

Forbidden:

```zig
const ms: u64 = @intCast(sec * 1000);
```

Correct:

```zig
const ms: u64 = @as(u64, @intCast(sec)) * 1000;
```

Reason:

```text
24.855 days = 2_147_483_647 milliseconds
sec = 2_147_484
sec * 1000 overflows i32 before the u64 cast
```

Invariant:

> `@intCast` after arithmetic does not make the arithmetic safe. Cast before the
> arithmetic when changing the numeric domain.

## 3. Wrapping ticks are not absolute timestamps

A `u32` millisecond tick wraps every 49.7 days.

Forbidden:

```zig
const last_ms: u64 = sdk_last_comm_time;
const elapsed_ms = now_uptime_ms - last_ms;
```

Correct:

```zig
const now_tick: u32 = @truncate(now_uptime_ms);
const elapsed_ms: u32 = now_tick -% sdk_last_comm_time;
```

Invariant:

> If a value is a fixed-width tick, compare it in that width using explicit
> wrapping arithmetic.

## 4. State belongs to the state machine

The edge node owns one coherent state. I/O callbacks may observe the world and
emit events, but they must not mutate core state directly.

Forbidden:

```text
callback -> mutate NodeState
callback -> start timer table
callback -> publish directly as policy
```

Correct:

```text
callback -> Event -> transition(state, event) -> Output actions
```

Invariant:

> The core decides. I/O reports.

## 5. Timeouts are derived, not scheduled as hidden state

Timeouts should be computed from state-entry timestamps and current monotonic
time. Avoid hidden active timer tables in I/O layers.

Correct model:

```text
state.mode_enter_ms + timeout_ms <= now_monotonic_ms
```

Invariant:

> A timeout is a consequence of state plus time, not a second state machine.

## 6. A2A is a first-class edge interface

An edge node is expected to communicate with other agents. A2A messages must be
modeled as explicit events and outputs.

Forbidden:

```text
hidden background message -> mutate state
implicit peer command -> direct hardware action
```

Correct:

```text
A2A inbound message -> Event
transition -> Output.send_a2a_message
transition -> Output.apply_actuator_command
```

Invariant:

> Peer communication is part of the state machine, not an exception to it.

## 7. Flexible software requires explicit contracts

The design goal is flexible software, not clever software.

Sussman-style flexibility means that a system remains understandable and
modifiable because its parts are explicit and recomposable.

Required properties:

- clear state ownership
- explicit time axes
- pure transitions
- replaceable I/O
- observable outputs
- boundary tests
- no silent catch-all branches

Invariant:

> Flexibility comes from explicit contracts. Hidden policy is rigidity disguised
> as convenience.

## 8. Boundary tests are mandatory

Happy-path tests are not enough for embedded time logic.

Every future time module must test:

- i32 millisecond overflow boundary: 24.855 days
- u32 millisecond wrap boundary: 49.7 days
- threshold minus one
- threshold plus one
- zero or uninitialized tick value
- target-width behavior on 32-bit and 64-bit assumptions

Invariant:

> If a boundary can be computed, it must be tested.
