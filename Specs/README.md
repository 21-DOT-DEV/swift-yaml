# Specs

Feature specs, **spec-kit-aligned but lightweight**: one numbered folder per feature
(`NNN-slug/`) with a canonical `plan.md` inside. We keep spec-kit's *folder convention* (so the
`speckit.*` workflow could be adopted later with no file moves) but skip its scripts/templates
machinery and create only the files we actually use. Each plan's roadmap **phase / feature mapping
lives in its header**, not the path — the spec number is a stable global counter, independent of
roadmap re-phasing.

> **Casing note:** this directory is intentionally `Specs/` (capitalized, matching `Roadmap/`).
> spec-kit's scripts default to lowercase `specs/`, so adopting that tooling later would need the
> path adjusted.

| # | Feature | Phase | Status | Plan |
|---|---|---|---|---|
| 001 | Mark/span shim — source-position bridge (`yamlx::mark` / `yamlx::valueSpan`) | 3 · F3 | Implemented | [plan.md](001-mark-span-shim/plan.md) |
| 002 | Surgical value set — change one value in place, comments preserved (`YAMLEditor.set`) | 3 · F1 | Implemented | [plan.md](002-surgical-value-set/plan.md) |
| 003 | Key/element removal — delete a leaf entry in place, comments preserved (`YAMLEditor.unset`) | 3 · F2 | Implemented | [plan.md](003-key-removal-unset/plan.md) |
| 004 | Spec-example conformance — decode the specification's overview examples and pin where we differ (tests only) | 6 · Hardening | Implemented | [plan.md](004-spec-conformance/plan.md) |
| 005 | Insert a missing scalar — fill a blank value or add a new key in place, comments preserved (`YAMLEditor.insert`) | 3 · F4 | Implemented | [plan.md](005-insert-scalar/plan.md) |
| 006 | Strict duplicate-key rejection — decoding throws on a repeated mapping key, detected exactly via a parser event hook (`DuplicateKeyStrategy.reject`) | 6 · F2 | Planned | [plan.md](006-duplicate-key-rejection/plan.md) |
