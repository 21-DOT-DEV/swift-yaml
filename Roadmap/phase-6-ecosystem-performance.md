# Phase 6 — Ecosystem, Performance & Hardening

**Status:** FUTURE
**Horizon:** Later
**Last Updated:** 2026-07-17

## Goal

Round out swift-yaml's fit, proof, and polish: pipeline conformances, stricter
opt-in safety, performance evidence, documentation, and the long-lead engine
question. This phase also records — honestly — the features that are
**blocked by the wrapped engine** so users and contributors aren't left
guessing why they're missing.

## Key Features

1. Combine `TopLevelDecoder` conformance — PLANNED
   - Purpose & user value: drop swift-yaml into Combine decode pipelines on
     Apple platforms.
   - Success metrics: `YAMLDecoder` conforms under `#if canImport(Combine)`
     (Input = `Data`); a pipeline test decodes end-to-end.
   - Dependencies: Phase 1.
   - Confidence: Medium — trivial, pure-Swift parity with Yams; gate so it
     doesn't cut against the cross-platform/Foundation-light posture.

2. Strict duplicate-key rejection (`.reject`) — PLANNED
   - Purpose & user value: config validators and security-sensitive loaders can
     reject documents with duplicate mapping keys instead of silently
     last-wins.
   - Success metrics: an opt-in `duplicateKeyStrategy` case rejects duplicates
     with a typed error and accurate position.
   - Dependencies: Phase 1.
   - Confidence: Medium — yaml-cpp keeps both entries of a repeated key, so
     detection uses a yaml-cpp `EventHandler`/pre-scan that flags the first
     repeat before the tree is built (shared with streaming below).
   - Notes: completes the existing `useFirst`/`useLast` strategy enum.

3. Performance benchmarks vs Yams — PLANNED
   - Purpose & user value: turn "should be fast (C++)" into evidence, and
     decide whether streaming is ever warranted.
   - Success metrics: a reproducible benchmark on a representative corpus,
     publishing encode/decode throughput vs Yams.
   - Dependencies: none.
   - Confidence: Low (needs-research) — currently unbenchmarked; no claim
     asserted until measured.

4. DocC documentation — PLANNED
   - Purpose & user value: discoverable API docs and a Yams → swift-yaml
     migration guide lower the adoption barrier.
   - Success metrics: public symbols documented; a published feature-parity
     matrix; a getting-started + migration article.
   - Dependencies: API stabilized through Phase 4.
   - Confidence: Medium — no docs today; hand off to the docc skills
     (docc-symbols / docc-articles / docc-audit).

5. yaml-cpp upstream bump (beyond 0.6.2) — FUTURE
   - Purpose & user value: pick up upstream fixes/features and re-evaluate
     currently-blocked capabilities (see Deferred). Out of scope for the
     overlay itself; a real maintenance item via the vendoring/sync ritual.

6. Streaming / SAX event API — FUTURE
   - Purpose & user value: event-driven processing of very large inputs without
     materializing the whole tree. Shares the `EventHandler` plumbing with
     strict duplicate-key detection; narrow audience, since `documentLimits`
     already addresses the DoS motivation.

7. Spec-example conformance suite — IMPLEMENTED
   - Purpose & user value: decode the YAML 1.2.2 spec's Chapter-2 overview
     examples and pin exactly where swift-yaml differs, so conformance is proven
     and every deviation is a recorded, intentional choice rather than a surprise.
   - Success metrics: the spec's overview examples decode (or are recorded as
     known issues); divergences live in a single manifest guarded with
     `withKnownIssue`; a subset cross-checks against `JSONDecoder`.
   - Status: **IMPLEMENTED** — merged to `main` (PR #6, 2026-07-15), delivered
     ahead of this FUTURE phase. `Tests/YAMLTests/SpecConformanceTests.swift`:
     28 examples — 23 clean, 3 intended (first-document-only), 2 known gaps
     (2.11 sequence keys, 2.23 multi-line `!!binary`) — green across the three
     passes. Tests-only: the sole product change was one doc sentence on
     `YAMLDecoder.decode` (first-document-only). Spec `Specs/004-spec-conformance/`.

## Deferred / Blocked

1. Comment-preserving **round-trip** (parse → mutate tree → re-emit) — DEFERRED
   (engine-blocked)
   - Purpose & user value: load a config into a value tree, mutate it freely,
     and re-emit while keeping comments (the ruamel.yaml use case).
   - Why blocked: verified firsthand and via upstream — yaml-cpp's parser
     discards comments (no `OnComment` event; feature requests open since 2012,
     unbuilt). It **cannot** be delivered on this engine.
   - Only unblock path: an upstream engine change (feature 5). The *surgical*
     subset — editing a value in place without re-emitting — does **not** need
     this and is committed as **Phase 3** (it sidesteps the engine by never
     serializing the tree). Emitting *new* comments programmatically is
     separately possible but low value.
   - Confidence: High — that round-trip is infeasible on 0.6.2 is well-evidenced.

## Dependencies & Sequencing

- Strict duplicate-key (2) and streaming (6) share a yaml-cpp `EventHandler`
  parse path — build that plumbing once.
- DocC (4) is most valuable after the Phase 4 API stabilizes.
- Comment round-trip (Deferred) is gated on the upstream bump (5); do not
  schedule it independently. Its surgical in-place subset is committed
  separately as Phase 3 (Now).

## Phase Metrics & Success Criteria

- This phase is successful when swift-yaml has published performance evidence,
  shipped DocC docs + a migration guide, offers strict-dup-key and Combine
  conformance for those who want them, and has an honest, documented stance on
  what the engine cannot do.

## Risks & Assumptions

- Upstream yaml-cpp is slow-moving; treat the bump as opportunistic, and never
  promise comment round-trip on the current engine.

## Phase Change Log

- 2026-07-17: Feature **7 (Spec-example conformance suite)** added and marked
  **IMPLEMENTED** — it had landed on `main` as **PR #6** (2026-07-15, 28 spec
  examples green with 2 recorded known issues) but had no roadmap entry, so the
  spec index/plan and this roadmap disagreed: a status drift, now reconciled (this
  file, the `Specs/004` plan header, and the `Specs/README` index). Delivered ahead
  of this FUTURE phase, which stays **FUTURE** (its other items are unstarted).
- 2026-06-17: Phase created (Later). Comment round-trip recorded as
  engine-blocked (DEFERRED); streaming + strict-dup-key noted as sharing the
  EventHandler path.
- 2026-06-20: Renumbered Phase 5 → 6. Split the deferred comment item — the
  surgical/in-place subset is now committed as Phase 3 (Now); full round-trip
  stays engine-blocked here.
