# Phase 4 — Public Model & Diagnostics

**Status:** PLANNED
**Horizon:** Next
**Last Updated:** 2026-06-20

## Goal

Promote the internal value tree to a supported public node type and build the
introspection features it unlocks: dynamic decoding when the shape isn't known
ahead of time, source marks for tooling, and tag awareness. This is the
keystone that closes the biggest *capability* gap versus Yams (which exposes a
public `Node`) and turns swift-yaml from a pure codec into a library that
tools, linters, and config loaders can build on.

## Key Features

1. Public node/value type + decode-to-`Any` — PLANNED
   - Purpose & user value: inspect or transform a parsed document without a
     `Codable` type, and decode dynamic/heterogeneous YAML (plugins, arbitrary
     config) into an inspectable tree.
   - Success metrics:
     - A public value type (promoted from the internal `YAMLValue`) with
       documented `Equatable`/`Hashable`/`Sendable` conformances and ergonomic
       accessors (subscripting, typed reads).
     - `decode(_:from:)` from a parsed node, and a path that yields the node
       (or `Any`) directly.
     - Encoding a node back produces equivalent YAML (node round-trip test).
   - Dependencies: Phase 1 model.
   - Confidence: Medium — Yams parity (public `Node`, per research); the
     internal model already exists, so the work is API design + a stability
     commitment.
   - Notes: this is the prerequisite for features 2 and 3 below; ship it
     deliberately and versioned.

2. Source marks (line/column) on decoded values — PLANNED
   - Purpose & user value: tools, linters, and config loaders can point users
     at the exact line/column of a value, not just parse errors.
   - Success metrics:
     - Decoded nodes/values expose a `mark` (1-based line/column).
     - A decoder accessor surfaces the mark for the value currently being
       decoded.
     - Marks verified against known fixture positions.
   - Dependencies: Public node type (feature 1).
   - Confidence: Medium — Yams exposes value marks (research); yaml-cpp
     `Node::Mark()` is available, so cost is low once the node type exists.

3. Tag support (inspect on decode, custom-tag coding) — PLANNED
   - Purpose & user value: read a value's YAML tag (e.g. distinguish
     `!!binary`, custom `!Foo`) and emit explicit tags when a type asks for
     them — needed for schema-aware and polymorphic payloads.
   - Success metrics:
     - A node exposes its tag; custom-tag encode/decode hooks round-trip a
       tagged value.
     - `!!binary`/`!!str`/custom local tags are inspectable and emittable.
   - Dependencies: Public node type (feature 1).
   - Confidence: Medium — Yams ships tag coding (research); yaml-cpp exposes
     `Tag` emitter manipulators and `Node::Tag()/SetTag()`.
   - Notes: biggest payoff is *reading* tags, so sequence after the node type;
     most Codable users won't need explicit tags day-to-day.

## Dependencies & Sequencing

- Local ordering: Public node type (1) **first** — marks (2) and tags (3) both
  ride on it.
- Cross-phase: builds on Phase 1; independent of Phase 2.

## Phase Metrics & Success Criteria

- This phase is successful when a caller can parse arbitrary YAML into an
  inspectable, documented public tree, ask any value for its source position,
  and read/write tags — without dropping to the C++ layer.

## Risks & Assumptions

- The public node type is a long-lived API surface; a hasty shape is costly to
  revise. Treat its release as a considered, versioned decision.

## Phase Change Log

- 2026-06-17: Phase created (Next), with the public node type as the explicit
  keystone for marks and tags.
- 2026-06-20: Renumbered Phase 3 → 4 after In-Place & Comment-Preserving
  Editing was inserted as Phase 3 (Now); scope unchanged.
