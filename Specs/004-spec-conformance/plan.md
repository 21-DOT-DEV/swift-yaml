# Plan — Phase 6 · Hardening: Spec-example conformance suite

| | |
|---|---|
| **Feature** | Roadmap **Phase 6 — Ecosystem, Performance & Hardening** ("fit, proof, and an honest, documented stance on what the engine does" — [Roadmap/phase-6-ecosystem-performance.md](../../Roadmap/phase-6-ecosystem-performance.md)), pulled forward as a cheap proof investment. A new **tests-only** file that decodes the YAML 1.2.2 specification's ~28 overview-chapter (Chapter 2) worked examples through `YAMLDecoder` and checks each against its specified meaning — cross-checked against Foundation's `JSONDecoder` wherever an example has a natural JSON equivalent. It turns "we inherit yaml-cpp's conformance, whatever that is" into a **written, enforced support surface**: exactly which spec constructs decode correctly, and — in one place — where and why we differ. The only product-code change is a one-sentence doc comment on the read function (first-document-only, below). |
| **Status** | **IMPLEMENTED — merged to `main`** (PR #6, 2026-07-15). Scope + design via the cold-reader Q&A (five unknowns) plus a follow-up review Q&A (multi-document doc gap, Unknown 1 = B). 28 examples implemented; three-pass green with 2 recorded known issues (§7). On landing, the `Specs/README.md` row was flipped to Implemented and a Phase 6 `Hardening` feature entry added. |
| **Decisions** (this session) | **D1 — Corpus (Q1 = B).** All ~28 examples in the specification's overview chapter (Chapter 2, the realistic little documents), tricky ones included — a conformance suite's value is completeness, and the tricky cases document where the engine bends the spec. *Out:* the deeper grammar chapters (5–10), which are parser edge cases that don't fit a decode-and-check shape. **D2 — Direction (Q2 = A).** Reading only (text → value). Writing-back is a separate concern already covered by `RoundTripTests`, and YAML is non-bijective (one value has many textual forms), so example-based write-back is the weakest form of round-trip testing — deferred to a future generator-based suite. **D3 — Assertion (Q3 = B).** Assert decoded values against hand-written expected values, **plus** an independent cross-check: for each example with a natural JSON twin, decode the equivalent JSON into the *same* Swift type via `JSONDecoder` and assert equality (the `OracleTests.decoderAgreesWithJSONDecoder` pattern). The JSON path never touches the YAML engine, so it catches both transcription slips and mapping bugs; anchor/custom-tag/multi-document examples (no clean JSON twin) fall back to hand-written values. **D4 — Divergence handling (Q4 = D).** Split by cause: a genuine spec shortfall → a **strict** known-issue (`withKnownIssue`) that asserts the *spec's* value, runs, and reports if it ever starts passing; a deliberate design choice (e.g. first-document-only) → record the actual behavior (a characterization assertion), safe *because* it is intended; a written reason on each; and every divergence listed once in this plan's **Deviation manifest** (§5.1). Grounding: pytest `xfail`/Swift `withKnownIssue` for gaps, characterization tests for intended behavior (with the documented caveat that blind pinning blesses bugs — hence "only where intended"), and the conformance-testing "implementation-defined vs bug" split (NIST). **D5 — Source location (Q5 = A).** Each example's YAML is written inline as a **multi-line raw-string literal** (`#"""…"""#`) in the test file, matching the existing tests (`EditorTests.example217` etc.) — so each test mirrors the spec's own layout (indentation and all); self-contained, input beside its check, no test-resource bundling; hand-copy risk is covered by the D3 JSON cross-check. |
| **Assumptions** (in force) | **A1** One new file `Tests/YAMLTests/SpecConformanceTests.swift`, `@Suite struct SpecConformance`, current swift-testing style; ~10–15 small shared `Codable` structs cover the repeated shapes. **A2** Examples transcribed **verbatim** from [yaml.org/spec/1.2.2 Chapter 2](https://yaml.org/spec/1.2.2/#chapter-2-language-overview), each labeled with its number, title, and a one-phrase gloss; a header comment cites the source. **A3** JSON twins are minimal equivalents written by hand next to their example; the cross-check reuses the existing `JSONDecoder`-agreement idiom. **A4** **Tests-only, save one documentation line:** no change to `Sources/` *logic*, `Package.swift`, the C++ shims, or vendored code — the sole product-file edit is a one-sentence doc comment on `YAMLDecoder.decode` recording the first-document-only behavior (Unknown 1 = B). Must-reject / negative inputs stay out of scope (owned by `SafetyTests`); the writing direction stays with `RoundTripTests`. **A5** Multi-document examples (2.7, 2.8, 2.28) are tested for the library's **first-document-only** behavior — an intended v1 contract (reading every document is planned as a *separate* `decodeAll` entry point, roadmap Phase 2), now stated in `YAMLDecoder.decode`'s user-facing doc comment (the one-sentence addition above) — and recorded as intentional deviations (§5.1). **A6** Verified on the three-pass ritual — `swift test`, `swift test -c release`, `swift run -c release --package-path Projects/InteropRepro` — with the suite green (known-issues count as expected, not failures). Left uncommitted for review; `Specs/README.md` row "Planned" now, "Implemented" at merge; a Phase 6 feature entry added at merge. |

## 1. Goal & success criteria

Document and **pin** exactly which YAML-specification constructs the library reads correctly, using the specification's own canonical examples, so the library's real 1.2 support surface is written down and enforced rather than assumed.

**Success criteria:**
- All ~28 Chapter-2 examples are represented (one test each, grouped by number).
- Each **clean** example decodes to its specified value; where a JSON twin exists, the YAML result equals the `JSONDecoder` result on the equivalent JSON.
- Each **divergence** is either a strict known-issue (asserts the spec value; alerts on unexpected pass) or a documented intentional choice — never a silent skip.
- Every divergence appears once in the **Deviation manifest** (§5.1), with a cause and a reason.
- The suite is green across all three passes; adding it changes no product behavior.

## 2. Scope

**In scope:** a new tests-only suite covering the ~28 Chapter-2 examples; the **decode** direction (`YAMLDecoder` → typed value); value assertions plus the `JSONDecoder` cross-check where a JSON twin is natural; divergence handling by cause (§D4); the deviation manifest.

**Out of scope (explicit owners):** the specification's chapters 5–10 grammar/character/directive examples — parser edge cases, wrong shape for a decode-and-check test; **must-reject / malformed** inputs — owned by `SafetyTests`; the **writing / round-trip** direction — owned by `RoundTripTests` (and better strengthened later by a value-generating property suite); the **full ~350-case community event suite** — it exercises the wrapped engine's event stream, needs an event API this overlay deliberately does not expose, and duplicates yaml-cpp's own conformance; any change to product-source *logic*, `Package.swift`, shims, or vendored code (the lone exception is the one-sentence first-document-only doc comment on `YAMLDecoder.decode`, Unknown 1 = B).

## 3. Design / approach

**Structure.** One `@Suite`, one `@Test` per example, named `example_2_NN_<slug>`. Each test:
1. holds the example's YAML as a verbatim raw-string literal;
2. decodes it with `YAMLDecoder().decode(Model.self, from: yaml)`;
3. asserts the decoded value equals the expected value;
4. **if a JSON twin exists:** decodes an equivalent JSON string with `JSONDecoder` into the *same* `Model` and asserts the two decoded values are equal.

**Models.** A handful of small shared `Codable` structs cover the recurring shapes — sequence-of-scalars (`[String]`), mapping-of-scalars, mapping-of-sequences, sequence-of-mappings, mapping-of-mappings, and a few bespoke ones (stats, invoice). Reused across examples that share a shape.

**Divergence handling (D4).**
- *Intentional choice* → assert the actual behavior with an inline comment, e.g. multi-document input decodes the **first** document only (documented library behavior). Manifest entry: cause = "intended".
- *Genuine gap* → `withKnownIssue("2.NN: <spec says X>, engine yields Y — <ref>") { #expect(decoded == specValue) }`. Runs, expects failure, and — being strict — flags an unexpected pass so we retire the annotation when the engine improves. Manifest entry: cause = "gap".

**Cross-check (D3).** The JSON twin is the independent witness: it decodes through Foundation, never through yaml-cpp, so agreement means our reader produced the semantically correct value (not just a value matching our own transcription).

### 3.1 Example inventory (pre-triage — buckets confirmed at implementation)

The spike proved the "clean" path (2.1/2.6/2.9/2.19/2.21 + block scalars all decoded correctly). Buckets below are the *expected* handling; implementation confirms each and files any surprises in §5.1.

| # | Title (gloss) | Shape / model | Expected bucket |
|---|---|---|---|
| 2.1 | Sequence of Scalars (a list of strings) | `[String]` | clean + JSON twin |
| 2.2 | Mapping Scalars to Scalars (key→value stats) | `{hr,avg,rbi}` | clean + JSON twin |
| 2.3 | Mapping Scalars to Sequences (key→list) | `{…:[String]}` | clean + JSON twin |
| 2.4 | Sequence of Mappings (list of records) | `[{name,hr,avg}]` | clean + JSON twin |
| 2.5 | Sequence of Sequences (rows of mixed types) | heterogeneous inner rows | **gap/limitation** — mixed String/Int/Double in one list resists typed decode |
| 2.6 | Mapping of Mappings (inline value maps) | `[String:{hr,avg}]` | clean + JSON twin (spiked) |
| 2.7 | Two Documents in a Stream | multi-document | **intended** — first document only |
| 2.8 | Play-by-Play Feed (stream) | multi-document | **intended** — first document only |
| 2.9 | Single Document with Two Comments | `{hr:[String],rbi:[String]}` | clean + JSON twin (spiked) |
| 2.10 | Node Anchors and References (reuse a node) | `{hr:[String],rbi:[String]}` | clean (alias expands on decode) |
| 2.11 | Mapping between Sequences (list-valued keys) | non-string keys | **gap/limitation** — Codable needs string keys |
| 2.12 | Compact Nested Mapping (list of records) | `[{item,quantity}]` | clean + JSON twin |
| 2.13 | Literal block scalar preserves newlines (root) | root `String` | triage — root scalar decode |
| 2.14 | Folded scalar (root) | root `String` | triage — root scalar decode |
| 2.15 | Folded newlines (root) | root `String` | triage — root scalar decode |
| 2.16 | Indentation determines scope | `{name,accomplishment,stats}` w/ block scalars | clean |
| 2.17 | Quoted Scalars (single/double, escapes) | `{unicode,control,…}` | clean (already in `EditorTests`) |
| 2.18 | Multi-line Flow Scalars | `{plain,quoted}` | clean |
| 2.19 | Integers (canonical/decimal/octal/hex) | `{…:Int}` | clean + JSON twin (spiked — inc. `0o`) |
| 2.20 | Floating Point (inc. `.inf`/`.nan`) | `{…:Double}` | triage — needs the non-conforming-float strategy |
| 2.21 | Miscellaneous (null, bools, leading-zero string) | `{booleans:[Bool],string}` | clean (spiked) |
| 2.22 | Timestamps | `{…}` dates | triage — date decoding strategy |
| 2.23 | Various Explicit Tags (inc. `!!binary`) | tagged values | **gap/limitation** — tag→type mapping |
| 2.24 | Global Tags (`%TAG`, custom shapes) | custom tags | **gap/limitation** — custom tags |
| 2.25 | Unordered Sets (`!!set`) | set tag | **gap/limitation** — tag |
| 2.26 | Ordered Mappings (`!!omap`) | omap tag | **gap/limitation** — tag |
| 2.27 | Invoice (rich realistic doc, anchors+dates) | bespoke `Invoice` model | clean-ish (larger model) |
| 2.28 | Log File (repeated-structure stream) | multi-document | **intended** — first document only |

Rough split: ~14 clean, ~4 triage (root scalars, floats, dates), ~7 gap/limitation (heterogeneous rows, non-string keys, tags), ~3 intentional (multi-doc). The gap/limitation tail is exactly the ~½-day of judgement work flagged in the estimate.

## 4. Tests

This feature *is* tests. The deliverable is the suite above, plus:
- **Oracle:** the D3 `JSONDecoder` cross-check for JSON-twin examples; hand-written expected values elsewhere.
- **Known-issue discipline:** every `withKnownIssue` carries a `2.NN` reference and a one-line reason; strict mode means a future engine fix surfaces as an unexpected pass.
- **No vacuous tests:** each example either asserts a concrete decoded value or is a documented `withKnownIssue` asserting the spec value — never an empty `try?`.

## 5. Risks & mitigations

- **Hand-transcription error** (wrong expected value passes silently). *Mitigation:* the D3 JSON twin is an independent witness; verbatim raw strings; example numbers labelled.
- **Characterization blesses a bug** (pinning actual behavior perpetuates a defect). *Mitigation:* pin **only** intentional choices; every *suspicious* divergence goes to a known-issue that asserts the **spec** value, so the spec stays the reference.
- **Known-issue rot** (a gap gets fixed but the annotation lingers). *Mitigation:* strict `withKnownIssue` — an unexpected pass is reported.
- **Corpus creep** into chapters 5–10. *Mitigation:* explicitly out of scope (§2).
- **More engine quirks than the spike suggested.** *Mitigation:* that discovery *is* the deliverable; each becomes a manifest entry and a known-issue; none blocks the suite from going green.
- **Root-scalar / date / float uncertainties** (2.13–2.15, 2.20, 2.22). *Mitigation:* triaged at implementation; resolved to clean (with the right decoder strategy) or to a documented manifest entry.

### 5.1 Deviation manifest (measured at implementation)

Of the 28 examples, **23 decode clean, 3 are intended first-document-only, 2 are genuine gaps.** The tail decoded far cleaner than the §3.1 pre-triage predicted (empirical triage beat the guess): reclassified to **clean** were 2.5 (mixed rows read cell-by-cell as text), 2.13–2.15 (root block scalars → `String`), 2.20 (the *default* decoder resolves `-.inf`/`.nan` and exponent forms), 2.22 (timestamps as YAML-1.2 core-schema strings), 2.24 (tags ignored, structure + anchors decode), 2.25 (`!!set` **is** a map-with-null-values — the spec's own representation), 2.26 (`!!omap` **is** a sequence-of-single-key-maps — likewise), and 2.27 (the whole invoice, anchors expanded).

| Example | Cause | Spec value | Actual behavior | Reason / handling |
|---|---|---|---|---|
| 2.7 Two Documents | intended | two documents | first document only | `decode` reads one document — a documented v1 contract; decode-all is Phase 2. Characterized. |
| 2.8 Play-by-Play | intended | two plays | first play only | same as 2.7. Characterized. |
| 2.28 Log File | intended | three log entries | first entry only | same as 2.7. Characterized. |
| 2.11 Mapping between Sequences | gap (overlay limitation) | a mapping keyed by a *sequence* | the non-string key collapses to `""` (data loss) | `Codable` requires string keys; the overlay maps a non-string key to `""`. Strict `withKnownIssue` — flips if ever represented or errored. |
| 2.23 `!!binary` value | gap | GIF bytes decoded from base64 | decode into `Data` throws | The base64 spans lines; the strict `Data` decoder rejects the embedded line breaks. Strict `withKnownIssue` — flips if ever decoded. (The example's `!!str` and custom-tag fields decode clean.) |

This table is the single "where and why we differ from the spec" record the whole suite points at.

## 6. Placement & verification

- **Files:** `Tests/YAMLTests/SpecConformanceTests.swift` (the suite) plus a one-sentence doc comment on `YAMLDecoder.decode` (first-document-only, Unknown 1 = B). No `Package.swift`/shim/vendored changes, no logic changes.
- **Three passes:** `swift test`; `swift test -c release`; `swift run -c release --package-path Projects/InteropRepro`.
- **On landing (done, 2026-07-17):** flipped the `Specs/README.md` 004 row to Implemented and this plan's Status to "merged to `main`"; added a Phase 6 `Hardening` feature entry ("Spec-example conformance suite") with its change-log line.

## 7. Status log

- **2026-07-15 (planned).** Scope + design via the cold-reader Q&A. Unknowns → **Q1 = B** (all ~28 Chapter-2 examples), **Q2 = A** (decode direction only), **Q3 = B** (value asserts + `JSONDecoder` cross-check on JSON twins), **Q4 = D** (split divergences by cause: strict `withKnownIssue` for gaps, characterization for intended behavior, single manifest), **Q5 = A** (inline raw-string literals). Grounding via web research: conformance-suite practice ([JSONTestSuite](https://github.com/nst/JSONTestSuite) accept/reject model), conformance-vs-round-trip separation and YAML non-bijectivity ([circe codec testing](https://circe.github.io/circe/codecs/testing.html)), characterization vs `xfail`/`withKnownIssue` ([pytest](https://docs.pytest.org/en/stable/how-to/skipping.html), [Ganssle](https://blog.ganssle.io/articles/2021/11/pytest-xfail.html), [characterization tests](https://en.wikipedia.org/wiki/Characterization_test)), and the "implementation-defined vs bug" split ([NIST](https://www.nist.gov/itl/ssd/information-systems-group/conformance-testing)). A 6-example spike (2.1/2.6/2.9/2.19/2.21 + block scalars) decoded cleanly — notably yaml-cpp 0.6.2 resolves YAML-1.2 `0o` octal — confirming the common path and bounding the judgement work to the tag/heterogeneous/non-string-key tail.
- **2026-07-15 (follow-up review + implemented).** A review flagged that the plan called the multi-document first-document-only behavior "documented" when it was only *implied* (the engine call reads one document; the decode doc said "document" singular; an internal design note deferred multi-doc) — never stated user-facing. Resolved via a one-question Q&A (**Unknown 1 = B**): added a one-sentence note to `YAMLDecoder.decode` (both overloads + the `Data` convenience) stating only the first document is read, and corrected the plan's wording — the sole product-file change; the rest is tests-only. Then implemented `Tests/YAMLTests/SpecConformanceTests.swift` (28 examples). Two empirical probes (retired) measured actual decode behavior before asserting, so buckets are measured not guessed; the tail decoded far cleaner than the §3.1 pre-triage predicted — **23 clean, 3 intended (first-document-only), 2 known gaps** (2.11 sequence keys collapse to `""`; 2.23 multi-line `!!binary` → `Data` throws), both strict `withKnownIssue`. 13 clean examples cross-check against `JSONDecoder` (§5.1). Green: 28 examples with 2 known issues, three passes.
- **2026-07-15 (post-implementation review — 3 findings, resolved).** (1) **Byte-overload doc drift** — the `[UInt8]` and `Data` `decode` overloads described first-document-only in their discussion but still labeled the `data` *parameter* "…YAML document"; updated both parameter labels to match the `String` overload ("…YAML text to read (first document only, if it is a stream)"), closing the skim-the-param-list gap. (2) **Plan/implementation drift on literal style** — D5 specified raw-string literals but the shipped suite used ordinary `"\n"`-escaped strings (a probe-convenience carryover); converted all 28 YAML inputs to **multi-line raw literals** (`#"""…"""#`) so the tests mirror the spec's layout — industry guidance favors multi-line/template literals for multi-line, whitespace-sensitive fixtures ("escaped newlines are hard to read and easy to mess up") — and the existing JSON cross-checks + expected values confirmed byte-equivalence (all 28 still green). D5 tightened accordingly. (3) **Unverified green claim** — re-ran the full three passes as evidence after the above edits. Grounded in doc-consistency/SSOT and multi-line-fixture-readability guidance.
- **2026-07-17 (status flip).** Feature landed on `main` as PR #6 but its status markers were never flipped (an overdue debt, caught in review). Flipped in a dedicated status commit: `Specs/README.md` 004 → Implemented, this plan's Status → "merged to `main`", and a new Phase 6 `Hardening` entry ("Spec-example conformance suite", IMPLEMENTED) added to `Roadmap/phase-6-ecosystem-performance.md` with a change-log line — batched with the same-overdue 005 flip.
