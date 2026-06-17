# Phase 1 — Codable Core & Safe Parsing

**Status:** COMPLETE
**Horizon:** Foundation
**Last Updated:** 2026-06-17

## Goal

Give Swift a drop-in `import YAML` codec with `JSONEncoder`/`JSONDecoder`
ergonomics: any `Codable` type serializes to and from YAML, parsing untrusted
input is safe by default, and the core carries no mandatory Foundation
dependency. This is the shipped foundation every later phase builds on.

## Key Features

1. Codable Encoder/Decoder — COMPLETE
   - Purpose & user value: developers serialize existing `Codable` models to
     YAML with no bespoke mapping, exactly as they would with JSON.
   - Success metrics:
     - Arbitrary `Codable` types round-trip (nested structs/enums/optionals/
       arrays/dictionaries, `CodingKeys`, class inheritance via
       `superEncoder`/`superDecoder`).
     - Output re-parses through yaml-cpp and agrees with `JSONDecoder` on a
       shared data model (independent-oracle tests pass).
     - `swift build` + `swift test` green (43 tests / 6 suites).
   - Dependencies: the wrap (`yamlcpp` + `yamlcppShims`).
   - Confidence: High — code + passing test suite in repo.

2. Encoding & decoding strategies — COMPLETE
   - Purpose & user value: control the wire shape without hand-written code —
     key casing, dates, data, and non-finite floats.
   - Success metrics:
     - `keyEncodingStrategy`/`keyDecodingStrategy` (snake_case + custom)
       round-trip.
     - Foundation-gated date (ISO-8601/epoch/custom) and data (base64/custom)
       strategies round-trip.
     - `nonConformingFloatEncodingStrategy` emits/parses native `.inf`/`.nan`.
   - Dependencies: Codable core.
   - Confidence: High — `FoundationSupport.swift` + strategy tests.
   - Notes: this strategy surface is a deliberate differentiator over Yams
     (whose encoder exposes only emitter-formatting options).

3. Safe-by-default parsing (`documentLimits`) — COMPLETE
   - Purpose & user value: parsing untrusted YAML cannot hang or exhaust
     memory — the overlay restores Swift's safe-by-default contract over an
     unsafe-by-default C++ parser.
   - Success metrics:
     - Alias-expansion ("billion laughs") bombs rejected within a node budget,
       no OOM/hang.
     - Pathological nesting (flow + compact-block + indentation) and oversized
       input rejected before the parser is reached.
     - Malformed input throws `DecodingError.dataCorrupted` with line/column.
   - Dependencies: Codable core.
   - Confidence: High — `documentLimits` + safety tests verified rejecting
     bombs.
   - Notes: configurable budgets + `.unbounded` opt-out; first-class
     configurable safety is a differentiator over the field.

4. Foundation-light core — COMPLETE
   - Purpose & user value: small, portable footprint for server/Linux — the
     codec core needs zero Foundation.
   - Success metrics:
     - The encoder/decoder, containers, errors, and scalar handling compile
       without Foundation; `Date`/`Data` live behind
       `#if canImport(FoundationEssentials/Foundation)`.
     - A Foundation-free `decode(from: [UInt8])` entry point exists.
   - Dependencies: Codable core.
   - Confidence: High — gating verified in `FoundationSupport.swift`.

## Dependencies & Sequencing

- All four features are shipped and interlocked; the wrap underpins them.
- Everything downstream (Phases 2–5) extends the serialization/walk + emitter
  boundary established here.

## Phase Metrics & Success Criteria

- This phase is successful when a Swift developer can `import YAML`, encode and
  decode their existing `Codable` types, and parse untrusted input safely —
  **met**, with a green test suite as evidence.

## Risks & Assumptions

- C++-interop virality is accepted and documented (semver-major).
- The approved design gate and done report live in `API-PROPOSAL.md`.

## Phase Change Log

- 2026-06-17: Recorded COMPLETE at roadmap creation; verified against the
  passing test suite and `API-PROPOSAL.md` done report.
