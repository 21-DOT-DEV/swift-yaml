# Phase 4 — Emission & Output Control

**Status:** PLANNED
**Horizon:** Next
**Last Updated:** 2026-06-17

## Goal

Give authors control over the *shape* of the YAML swift-yaml emits: explicit
document markers, readable multi-line strings, and optional anchor/alias reuse.
Today output is a single document in block or flow style with auto-quoting;
this phase brings the emitter closer to Yams' formatting surface where it is
feasible on yaml-cpp 0.6.2 (and deliberately drops what isn't).

## Key Features

1. Explicit document markers (`---` / `...`) — PLANNED
   - Purpose & user value: emit a leading `---` and/or trailing `...` so output
     is valid as a stream entry and matches tool expectations (Kubernetes,
     multi-doc pipelines).
   - Success metrics:
     - Encoder options toggle explicit start/end markers.
     - Output with markers re-parses identically; pairs with Phase 2 multi-doc
       emit.
   - Dependencies: Phase 1 emitter boundary.
   - Confidence: Medium — `BeginDoc`/`EndDoc` manipulators confirmed in
     yaml-cpp 0.6.2.

2. Block scalar styles (literal `|`, folded `>`) — PLANNED
   - Purpose & user value: multi-line string values (scripts, certificates,
     prose) emit as readable block scalars instead of escaped one-liners.
   - Success metrics:
     - An encoder option emits newline-bearing strings as literal/folded block
       scalars; values round-trip unchanged.
     - Auto-quoting still guarantees type-preservation for ambiguous scalars.
   - Dependencies: Phase 1 emitter boundary.
   - Confidence: Medium — `Literal`/`SingleQuoted`/`DoubleQuoted` manipulators
     confirmed; must be driven via the Emitter path (yaml-cpp's node `Style()`
     axis is Block/Flow only, no scalar-quote axis).

3. Anchor/alias emission (opt-in) — FUTURE
   - Purpose & user value: collapse repeated subtrees into `&anchor`/`*alias`
     for compact output (we already *decode* aliases; this is the emit side).
   - Dependencies: Phase 1 emitter boundary.
   - Confidence: Low (needs-research) — feasible (`Anchor`/`Alias`
     manipulators) but demand is narrow and redundancy detection is the hard
     part; opt-in only, since auto-aliasing changes output shape and can
     surprise.

## Dependencies & Sequencing

- Local ordering: markers + block scalars (cheap, high readability payoff)
  before anchor emission (narrow, heavier).
- Cross-phase: document markers complete the Phase 2 multi-document emit story.

## Phase Metrics & Success Criteria

- This phase is successful when authors can emit stream-ready, human-readable
  YAML — explicit markers, block scalars for multi-line text — with anchor
  reuse available as a deliberate opt-in.

## Risks & Assumptions

- **Excluded (engine limit):** line-width / wrapping control — verified absent
  from yaml-cpp 0.6.2's emitter (no width knob). Not on this engine.
- **FUTURE, low value:** non-ASCII escaping toggles and bool/int-base
  formatting (`yes/no`, hex/oct) — feasible via manipulators but niche and in
  tension with stable Codable semantics; add only on request.

## Phase Change Log

- 2026-06-17: Phase created (Next). Line-width control excluded as
  engine-infeasible; anchor emission scoped as opt-in/FUTURE.
