# Notes from External References

This file captures patterns *read* from external reference repositories
listed in [AGENTS.md § 1.1 External reference repos](AGENTS.md#11-external-reference-repos).

## Rules for this file

- Capture **patterns and observations**, not code. Verbatim code does not
  belong here.
- Each note must cite the external repo and, when useful, a path inside
  it (e.g. `zig-esp-idf-sample / build.zig`).
- Notes are durable. They should still make sense after the local clone
  of an external repo is gone.
- If a note grows into a real design rule, promote it into
  `INVARIANTS.md`, `PROFILE.md`, `ENVELOPE.md`, `REGISTRY.md`, or
  `INGEST.md` and remove it from here.
- This file does not direct firmware. It only records what we learned by
  reading.

## Template

```
### YYYY-MM-DD — short title

- source:   <repo name> / <path within repo>
- context:  what we were trying to understand
- pattern:  one or two paragraphs describing the pattern, in our own
            words, never as quoted source code
- our take: how (or whether) it informs the edge agent design here
```

## Notes

(none yet — Phase 0 is in progress; first entries will land once the
external sample is built and monitored)
