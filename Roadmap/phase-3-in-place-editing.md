# Phase 3 — In-Place & Comment-Preserving Editing

**Status:** ACTIVE
**Horizon:** Now
**Last Updated:** 2026-06-20

## Goal

Let callers change values in an existing YAML document **without re-emitting
it** — so comments, blank lines, key order, and quoting survive byte-for-byte
everywhere except the span actually edited. This is the surgical subset of the
comment story: it sidesteps the engine limitation (yaml-cpp discards comments on
parse) by never going parse→mutate→serialize. Full round-trip stays
engine-blocked and deferred (Phase 6). The motivating use case is `config set`:
update one value in a hand-maintained config and produce a one-line diff, not a
reformatted file.

## Key Features

1. Surgical value set — PLANNED
   - Purpose & user value: `set(path, value)` over the original source text
     changes a scalar in place; comments, ordering, indentation, and quoting
     elsewhere are untouched. The diff is limited to the edited value.
   - Success metrics:
     - Changing a value preserves every comment, blank line, and key order in
       the document; the textual diff covers only the edited span.
     - The result re-parses to the intended new value (oracle: re-parse through
       yaml-cpp, an independent path from the edit).
     - A missing/unaddressable path returns a typed error, never a silent no-op.
   - Dependencies: Phase 1 parse boundary + the Mark/span shim (feature 3).
   - Confidence: Medium-High — `Node::Mark()` is confirmed present in yaml-cpp
     0.6.2; the approach avoids the comment-discarding engine path entirely.
   - Notes: end-of-span for a plain scalar on its own line is trivial; flow
     collections and multi-line (block/quoted) scalars are the fiddly cases —
     scope and test them explicitly.

2. Key removal (`unset`) — PLANNED
   - Purpose & user value: delete a key and its value in place, leaving
     neighbouring entries and their comments intact.
   - Success metrics:
     - Removing a key leaves sibling keys, blank lines, and comments unchanged;
       the document still parses.
   - Dependencies: feature 1's locate-by-`Mark` machinery.
   - Confidence: Medium — line/range deletion reuses the span logic; trailing
     vs. leading comment ownership is the edge to pin down with fixtures.

3. Mark/span shim — PLANNED
   - Purpose & user value: expose a parsed node's source position
     (`Node::Mark()`, line/column) and a way to compute its value's end span, so
     the Swift layer can locate exactly what to splice.
   - Success metrics:
     - An authored `yamlx::` helper returns a node's mark; spans verified
       against known fixture positions.
   - Dependencies: none beyond the existing wrap.
   - Confidence: High — `Node::Mark()` is already in the vendored headers;
     authored shim only, **no vendored-file edits** (per `AGENTS.md`).
   - Notes: the same Mark exposure feeds Phase 4's source-marks feature — build
     it once, here, and reuse.

## Out of Scope (stated, to keep the comment story honest)

- **Full parse→mutate→emit round-trip** with comment retention — it normalizes
  formatting and is engine-blocked; remains DEFERRED in Phase 6.
- **Inserting brand-new nested keys** into commented structure (indentation and
  comment-association guesswork) — drifts toward a comment-aware DOM; out of
  scope for the surgical approach.

## Dependencies & Sequencing

- Local ordering: Mark/span shim (3) first → surgical set (1) → unset (2).
- Cross-phase: builds on Phase 1; independent of and co-active with Phase 2.
  Splits the surgical subset out of Phase 6's deferred comment item; the shim
  also feeds Phase 4's source marks.

## Phase Metrics & Success Criteria

- This phase is successful when a real, hand-commented config file can have a
  value changed (or a key removed) and re-saved with the change as the only
  textual diff — comments, ordering, and formatting byte-identical elsewhere —
  and the result re-parses to the intended data.

## Risks & Assumptions

- **Not round-trip.** This must never be described as comment round-trip; it is
  in-place editing that preserves comments precisely because it does not
  re-emit. The guardrail "never promise comment round-trip on this engine"
  (Phase 6) stands.
- Span detection for flow collections and multi-line scalars is the main
  implementation risk; bound it with spec-derived fixtures, not our own output.

## Phase Change Log

- 2026-06-20: Phase created (Now), co-active with Phase 2. Split from Phase 6's
  deferred "comment preservation & round-trip" item — the surgical/in-place
  subset is feasible on yaml-cpp 0.6.2 and committed here; full round-trip stays
  engine-blocked (Phase 6).
