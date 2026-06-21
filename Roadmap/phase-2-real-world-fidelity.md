# Phase 2 — Real-World YAML Fidelity

**Status:** ACTIVE
**Horizon:** Now
**Last Updated:** 2026-06-20

## Goal

Make swift-yaml correctly decode and emit the YAML that real-world configs
actually contain. Today a Kubernetes manifest, Docker Compose file, or CI
workflow that uses merge keys or multiple documents either loses data silently
or fails — closing those gaps is the highest-leverage work because it is about
*correctness on common input*, not new surface area.

## Key Features

1. Merge keys (`<<`) — PLANNED
   - Purpose & user value: documents that DRY out repetition with
     `<<: *anchor` (ubiquitous in Kubernetes/Compose/CI) decode to the merged
     result instead of silently dropping keys or throwing.
   - Success metrics:
     - A mapping with `<<` merges the referenced mapping(s), with local keys
       taking precedence (per the YAML merge spec).
     - A sequence of merge sources merges in order (earlier wins).
     - Real Compose/K8s fixtures using `<<` decode with zero key loss.
     - Behavior is configurable (honor vs treat-as-literal-key) and on by
       default.
   - Dependencies: Phase 1 serialization walk.
   - Confidence: Medium — firsthand-verified that yaml-cpp does **not** resolve
     `<<` (decode currently yields a literal `<<` key / typeMismatch); the fix
     is feasible in our own `build()` walk.
   - Notes: must be resolved in the Swift walk — yaml-cpp's `Load` won't do it.

2. Multi-document streams — PLANNED
   - Purpose & user value: parse and emit `---`-separated document streams
     (Kubernetes applies many manifests from one file; logs/records stream as
     multiple docs).
   - Success metrics:
     - A `decode`-all entry point returns one decoded value per document.
     - An encode-many entry point emits N documents separated by `---`.
     - A multi-doc K8s fixture round-trips document-for-document.
   - Dependencies: Phase 1; pairs with explicit document markers (Phase 5).
   - Confidence: Medium — `LoadAll` (parse) and `BeginDoc`/`EndDoc` (emit) are
     confirmed available in yaml-cpp 0.6.2.
   - Notes: settle the API shape (`[T]` vs a lazy stream) in the design spec.

3. Native YAML timestamp resolution — PLANNED
   - Purpose & user value: a `tag:yaml.org,2002:timestamp` (or an unquoted
     ISO-8601 scalar) decodes to `Date` by default, matching Yams and what YAML
     authors expect.
   - Success metrics:
     - Tagged and ISO-8601 timestamp scalars decode to `Date` without a custom
       strategy.
     - Interaction with the existing `dateDecodingStrategy` has documented,
       predictable precedence.
     - A bare integer is **not** silently treated as a timestamp (documented to
       avoid a known cross-library confusion).
   - Dependencies: Phase 1; reuses the existing arithmetic ISO-8601 codec.
   - Confidence: Medium — Yams ships this in its default resolver (research);
     `Node::Tag()` is available; Foundation-gated like the other date work.

## Dependencies & Sequencing

- Local ordering: Merge keys first (correctness, self-contained) → multi-doc →
  timestamp. None blocks the others.
- Cross-phase: multi-document pairs naturally with explicit `---`/`...` markers
  in Phase 5 (emit side).

## Phase Metrics & Success Criteria

- This phase is successful when representative Kubernetes, Docker Compose, and
  GitHub Actions YAML decodes through swift-yaml with no data loss — merge keys
  honored, every document in a stream recovered, timestamps typed as `Date`.

## Risks & Assumptions

- Merge precedence and recursive/nested merges have spec subtleties; cover them
  with fixtures drawn from the spec, not from our own output.
- Multi-document API shape is a public commitment — choose it deliberately.

## Phase Change Log

- 2026-06-17: Phase created (Now). Merge keys prioritized first as a
  firsthand-verified correctness gap.
- 2026-06-20: Cross-references renumbered (Phase 4 → 5) after In-Place Editing
  was inserted as Phase 3 (Now).
