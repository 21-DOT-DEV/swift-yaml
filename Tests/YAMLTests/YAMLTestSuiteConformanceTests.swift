//  Parser error-case conformance, sourced from the YAML Test Suite
//  (https://github.com/yaml/yaml-test-suite) — a language-independent YAML 1.2
//  conformance corpus. Each case below keeps its upstream four-character ID and
//  label; the `yaml` inputs are copied verbatim from the suite's `error` cases
//  (inputs a conformant parser MUST reject).
//
//  Verdicts were *measured* against the vendored engine (yaml-cpp 0.6.2), not
//  assumed: it rejects only some of these. The rest are pinned as documented
//  `withKnownIssue` deviations (parser leniency) that flip to a hard failure if a
//  future engine tightens — the deviation-manifest approach from
//  `SpecConformanceTests` (spec 004). Multi-document / directive-boundary error
//  cases (e.g. RHX7, EB22, 3HFZ, QLJ7) are deferred: they entangle with the
//  decoder's documented first-document-only scope rather than testing single-
//  document parse rejection.
//
//  ── The copied inputs are used under the MIT License ───────────────────────────
//  MIT License
//
//  Copyright (c) 2016-2020 Ingy döt Net
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//  ───────────────────────────────────────────────────────────────────────────────

import Testing
import YAML

@Suite struct YAMLTestSuiteConformance {

    /// An empty shape: decoding it succeeds for any mapping and fails with a
    /// *type mismatch* (not a parse error) for any other well-formed document —
    /// so the only way ``parseRejected`` returns `true` is a genuine parser
    /// rejection, independent of each case's shape.
    private struct Probe: Decodable {}

    /// True iff the engine rejects `yaml` at **parse** time — a `DecodingError`
    /// wrapping ``YAMLError/parse(message:line:column:)`` — as opposed to
    /// accepting it or failing later on shape.
    private func parseRejected(_ yaml: String) -> Bool {
        do {
            _ = try YAMLDecoder().decode(Probe.self, from: yaml)
            return false                                  // parsed and decoded
        } catch let DecodingError.dataCorrupted(ctx) {
            if case .parse = ctx.underlyingError as? YAMLError { return true }
            return false                                  // e.g. duplicateKey / tooComplex
        } catch {
            return false                                  // type mismatch → parse succeeded
        }
    }

    /// One suite `error` case, with the verdict measured against yaml-cpp 0.6.2.
    struct ErrorCase: Sendable, CustomTestStringConvertible {
        let id: String            // yaml-test-suite case ID
        let label: String         // its `===` label
        let yaml: String          // verbatim `in.yaml`
        let engineRejects: Bool   // measured: does the vendored engine reject it?
        var testDescription: String { "\(id) — \(label)" }
    }

    static let cases: [ErrorCase] = [
        // ── Rejected by yaml-cpp 0.6.2 — regression guards ──
        .init(id: "T833", label: "Flow mapping missing a separating comma",
              yaml: "---\n{\n foo: 1\n bar: 2 }\n", engineRejects: true),
        .init(id: "DK4H", label: "Implicit key followed by newline",
              yaml: "---\n[ key\n  : value ]\n", engineRejects: true),
        .init(id: "U99R", label: "Invalid comma in tag",
              yaml: "- !!str, xxx\n", engineRejects: true),
        .init(id: "SR86", label: "Anchor plus Alias (both on one node)",
              yaml: "key1: &a value\nkey2: &b *a\n", engineRejects: true),

        // ── Accepted by yaml-cpp 0.6.2 — documented leniency deviations ──
        .init(id: "9JBA", label: "Invalid comment after end of flow sequence",
              yaml: "---\n[ a, b, c, ]#invalid\n", engineRejects: false),
        .init(id: "CVW2", label: "Invalid comment after comma",
              yaml: "---\n[ a, b, c,#invalid\n]\n", engineRejects: false),
        .init(id: "SU5Z", label: "Comment without whitespace after doublequoted scalar",
              yaml: "key: \"value\"# invalid comment\n", engineRejects: false),
        .init(id: "9C9N", label: "Wrong indented flow sequence",
              yaml: "---\nflow: [a,\nb,\nc]\n", engineRejects: false),
        .init(id: "CTN5", label: "Flow sequence with invalid extra comma",
              yaml: "---\n[ a, b, c, , ]\n", engineRejects: false),
        .init(id: "G5U8", label: "Plain dashes in flow sequence",
              yaml: "---\n- [-, -]\n", engineRejects: false),
    ]

    /// Every suite `error` input must be rejected at parse time. Where yaml-cpp
    /// 0.6.2 is instead lenient, the expectation is wrapped in `withKnownIssue`
    /// so the deviation is recorded (not a red build) and trips if the engine
    /// ever starts rejecting it — prompting removal of the wrapper.
    @Test(arguments: YAMLTestSuiteConformance.cases)
    func rejectsMalformedInput(_ c: ErrorCase) {
        if c.engineRejects {
            #expect(parseRejected(c.yaml), "\(c.id) (\(c.label)) must be rejected at parse time")
        } else {
            withKnownIssue("yaml-cpp 0.6.2 accepts \(c.id) (\(c.label)); the spec requires rejection") {
                #expect(parseRejected(c.yaml))
            }
        }
    }
}
