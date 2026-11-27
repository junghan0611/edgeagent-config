# Changelog

## Unreleased

## v2026.11.27 — Common edge firmware frame

First public documentation snapshot. No deployable firmware or cross-platform
runtime is included.

- Expanded the project from an ESP-focused concept into a public common edge
  firmware frame. Roles are composed from functions and capabilities; product
  policy, target configuration, and hardware/safety evidence stay with products.
- Described local controllers and replaceable network helpers, including
  distinct delivery, acceptance, completion, and observation; result lookup
  after interruptions; and no automatic replay of unresolved requests.
- Set the next checkpoint as synthetic host replay. Kept the existing
  Python/CBOR envelope smoke separate from that replay, and kept NodeCard,
  transport, and implementation choices out of its prerequisites.
- Collected the previous Phase 0 ESP32 bench observations, the host/firmware
  shell split, and the core/home/edge responsibility and trust boundaries.
  ESP32 / M5Stack remains the measured bench; broader target support has not
  been verified.

Verification: the host Nix shell evaluated and `./run.sh hello-edge` passed.
Full `nix flake check --no-build` remains blocked in the unchanged ESP-IDF
shell while resolving its source during evaluation; the pre-release `main`
revision reproduced the same failure. No hardware was used.
