# Product Roadmap — swift-yaml

**Version:** v1.0.0
**Last Updated:** 2026-06-17

## Vision & Goals

- **Vision:** swift-yaml is the idiomatic, safe, Foundation-light YAML library
  for Swift — `JSONEncoder`/`JSONDecoder` ergonomics for YAML, built on
  yaml-cpp.
- **Target users:** Swift developers on Apple platforms **and** Linux/server
  who need YAML for configuration and data interchange through `Codable`;
  teams migrating from Yams who want richer encoding strategies and
  safe-by-default parsing.
- **Top outcomes:**
  1. Any `Codable` type round-trips to/from YAML with the same ergonomics as
     JSON — no bespoke mapping.
  2. Parsing untrusted YAML is safe by default (resource-bounded) with zero
     configuration.
  3. The library stays lightweight and portable — no mandatory Foundation,
     identical behavior on Linux and Apple platforms.

## Phases Overview

| Horizon | Phase | Name / Goal | Status | Detail |
|---|---|---|---|---|
| Foundation | 1 | Codable Core & Safe Parsing — drop-in `import YAML` codec | COMPLETE | [phase-1](docs/roadmap/phase-1-codable-core.md) |
| Now | 2 | Real-World YAML Fidelity — read/write the YAML configs actually contain | ACTIVE | [phase-2](docs/roadmap/phase-2-real-world-fidelity.md) |
| Next | 3 | Public Model & Diagnostics — expose the tree, marks, and tags | PLANNED | [phase-3](docs/roadmap/phase-3-public-model-diagnostics.md) |
| Next | 4 | Emission & Output Control — shape and style the emitted YAML | PLANNED | [phase-4](docs/roadmap/phase-4-emission-control.md) |
| Later | 5 | Ecosystem, Performance & Hardening — fit, proof, and polish | FUTURE | [phase-5](docs/roadmap/phase-5-ecosystem-performance.md) |

- **Phase 1 (done):** the wrap (yaml-cpp 0.6.2 + `yamlcppShims`) and the
  `YAMLEncoder`/`YAMLDecoder` Codable overlay with encoding strategies, safety
  budgets, and a Foundation-light core. 43 tests green.
- **Phase 2 (now):** merge keys (`<<`), multi-document streams, native
  timestamp resolution — the gaps that make real Kubernetes/Compose/CI YAML
  decode correctly.
- **Phase 3 (next):** promote the internal value tree to a public node type
  with decode-to-`Any`, source marks (line/column), and tag support.
- **Phase 4 (next):** explicit document markers, block scalar styles, opt-in
  anchor/alias emission.
- **Phase 5 (later):** Combine conformance, strict duplicate-key rejection,
  benchmarks vs Yams, DocC docs, an upstream yaml-cpp bump — and the
  engine-blocked items recorded honestly.

## Product-Level Metrics & Success Criteria

- **Codable parity:** every type in a shared corpus that round-trips through
  `JSONEncoder`/`JSONDecoder` also round-trips through swift-yaml.
- **Real-world compatibility:** representative Kubernetes manifests, Docker
  Compose files, and GitHub Actions workflows decode without data loss
  (including merge keys and multi-document streams) — target by end of Phase 2.
- **Safe on untrusted input:** a YAML attack corpus (alias bombs, deep
  nesting, oversized payloads) is rejected within bounded time and memory —
  zero hangs/OOM/crashes.
- **Lightweight & portable:** `import YAML` pulls in no Foundation on Linux;
  CI is green on macOS and Linux for every release.
- **Diagnosable:** decode failures carry line/column; decoded values expose
  source marks once Phase 3 lands.
- **Migratable:** a published Yams → swift-yaml feature-parity matrix and
  migration note; the differentiators below are never regressed.
- **Documented & stable:** the public API ships DocC documentation and follows
  semantic versioning (C++-interop virality is a stated semver-major contract).

## High-Level Dependencies & Sequencing

- Phases 2 and 4 build directly on Phase 1's serialization/walk + emitter
  boundary; no new prerequisites.
- Phase 3 is the **keystone for introspection**: source marks, tag inspection,
  and dynamic decode all depend on the public node type landing first.
- In Phase 5, strict duplicate-key rejection and streaming/SAX share a
  yaml-cpp `EventHandler`-based parse path; **comment round-trip depends on an
  upstream engine change** (Phase 5's yaml-cpp bump) and is otherwise blocked.

## Global Risks & Assumptions

- **Assumption — engine is yaml-cpp 0.6.2 (pinned).** Verified firsthand: its
  parser *discards comments* and *does not resolve merge keys* (we resolve `<<`
  in our own walk), and its emitter has *no line-width knob* (line-wrapping is
  excluded from scope). These shape Phases 2, 4, and 5.
- **Assumption — C++ interop is viral.** Consumers must enable
  `.interoperabilityMode(.Cxx)`; enabling/disabling it is semver-major. Stated,
  not hidden.
- **Assumption — positioning** (idiomatic/safe/Foundation-light, Yams as the
  incumbent comparator) is inferred from the codebase and a feature-gap
  analysis, not a written product brief — correct here if it diverges.
- **Risk — public-node API is a stability commitment** (Phase 3): ship it
  deliberately and versioned; a rushed node type is expensive to change.
- **Risk — upstream yaml-cpp moves slowly** (comment-event support has been
  open ~9 years): do not promise comment round-trip on this engine.
- **Differentiators to preserve (never regress):** encoding strategies (Yams
  has none), first-class configurable safety budgets, the Foundation-light
  core, the `Sendable` option surface, and Codable "Norway problem" immunity
  (per-type scalar resolution).

## Change Log

- v1.0.0 (2026-06-17): Initial roadmap created from the shipped overlay
  (verified via `swift build`/`swift test`, 43 tests) and a cited deep-research
  feature-gap analysis vs Yams and the YAML ecosystem. Merge-key support
  elevated to the Now horizon as a firsthand-verified correctness gap; comment
  round-trip recorded as engine-blocked (DEFERRED).
