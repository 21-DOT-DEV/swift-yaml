import Testing
import yamlcppShims  // re-exports the vendored yamlcpp module (YAML.Load / Dump / ...)

// Inputs are YAML 1.2 spec examples lifted from yaml-cpp's own
// test/specexamples.h (examples 2.1 and 2.2) — the authoritative corpus
// upstream ships, cited rather than fabricated.

@Suite struct ParseAndEmit {
    // spec example 2.1 — a sequence of scalars.
    static let sequenceYAML = """
        - Mark McGwire
        - Sammy Sosa
        - Ken Griffey
        """

    // spec example 2.2 — a map of scalar values.
    static let mappingYAML = """
        hr:  65    # Home runs
        avg: 0.278 # Batting average
        rbi: 147   # Runs Batted In
        """

    @Test func parsesSequenceStructure() {
        let root = Self.sequenceYAML.withCString { YAML.Load($0) }
        #expect(root.IsSequence())
        #expect(root.size() == 3)
    }

    @Test func parsesMappingStructure() {
        let root = Self.mappingYAML.withCString { YAML.Load($0) }
        #expect(root.IsMap())
        #expect(root.size() == 3)
    }

    @Test func extractsTypedScalars() {
        let root = Self.mappingYAML.withCString { YAML.Load($0) }
        #expect(yamlx.asInt(yamlx.at(root, "hr")) == 65)
        #expect(yamlx.asInt(yamlx.at(root, "rbi")) == 147)
    }

    @Test func scalarTextRoundTrips() {
        let root = Self.sequenceYAML.withCString { YAML.Load($0) }
        #expect(String(yamlx.asString(yamlx.atIndex(root, 0))) == "Mark McGwire")
    }

    @Test func emitsParsedDocument() {
        let root = Self.sequenceYAML.withCString { YAML.Load($0) }
        #expect(String(YAML.Dump(root)).contains("Mark McGwire"))
    }
}

// Phase 3 · feature 3 — the source-position bridge (yamlx::mark / yamlx::valueSpan).
// Positions are checked against known spec-example fixtures, and the reliable-vs-
// deferred boundary is pinned with small authored fixtures. See
// Specs/001-mark-span-shim/plan.md.
@Suite struct MarkAndSpan {

    // Look up a map value by key and take its source span, using the same source
    // bytes the document was parsed from. The returned Span is plain integers, so
    // it is safe to hand back out of the withCString scope.
    private func span(ofKey key: String, in text: String) -> yamlx.Span {
        let byteCount = text.utf8.count
        return text.withCString { src in
            let root = yamlx.parse(src).root
            return key.withCString { k in
                yamlx.valueSpan(yamlx.at(root, k), src, Int(byteCount))
            }
        }
    }

    // A plain, single-line scalar returns a reliable span at the hand-verified
    // line/column whose bytes decode back to the value (spec example 2.2).
    @Test func reliableSpanForPlainScalar() {
        let text = ParseAndEmit.mappingYAML   // hr:  65 / avg: 0.278 / rbi: 147
        let bytes = Array(text.utf8)

        func check(_ key: String, _ value: String, line: Int, column: Int) {
            let s = span(ofKey: key, in: text)
            #expect(s.ok)
            #expect(s.endReliable)
            #expect(s.line == line)
            #expect(s.column == column)
            #expect(String(decoding: bytes[Int(s.pos) ..< Int(s.end)], as: UTF8.self) == value)
        }

        check("hr", "65", line: 0, column: 5)
        check("avg", "0.278", line: 1, column: 5)
        check("rbi", "147", line: 2, column: 5)
    }

    // Quoted, block, flow, empty, and wrapper-quote-prefixed values all withhold
    // the end (endReliable == false) while still reporting a valid start.
    @Test func deferredShapesWithholdEnd() {
        let cases: [(src: String, label: String)] = [
            ("k: \"65\"",     "double-quoted"),
            ("k: 'ab'",       "single-quoted"),
            ("k: [1, 2]",     "flow collection (not a scalar)"),
            ("k: |\n  hello", "literal block, multi-line"),
            ("k: long\n value", "multi-line folded plain (only the memcmp guard defers this)"),
            ("k: \"\"",       "empty double-quoted"),
            ("k: ''",         "empty single-quoted"),
            ("k: |\n",        "empty literal block"),
            ("k: ''''",       "single-quote value ' (wrapper-quote prefix)"),
            ("k: ''''''",     "single-quote value '' (wrapper-quote prefix)"),
            ("k: \"\\\"\"",   "double-quote value \" (wrapper-quote prefix)"),
        ]
        for c in cases {
            let s = span(ofKey: "k", in: c.src)
            #expect(s.ok, "start should be valid: \(c.label)")
            #expect(!s.endReliable, "end must be withheld: \(c.label)")
        }
    }

    // An undefined node (missing key) reports ok == false and never crashes.
    @Test func undefinedNodeIsNotOK() {
        let text = "a: 1"
        text.withCString { src in
            let root = yamlx.parse(src).root
            let missing = "nope".withCString { yamlx.at(root, $0) }
            #expect(!yamlx.mark(missing).ok)
            #expect(!yamlx.valueSpan(missing, src, Int(text.utf8.count)).ok)
        }
    }

    // mark() reports a start for a root sequence (position-only; end withheld).
    @Test func markReportsCollectionStart() {
        let text = ParseAndEmit.sequenceYAML   // a block sequence of three scalars
        text.withCString { src in
            let root = yamlx.parse(src).root
            let m = yamlx.mark(root)
            #expect(m.ok)
            #expect(m.line == 0)
            #expect(!yamlx.valueSpan(root, src, Int(text.utf8.count)).endReliable)
        }
    }

    // mark() reports a nested MAP's start too — the map-node path the sequence
    // case above can't reach. Together they cover the "any node" position claim.
    @Test func markReportsNestedMapStart() {
        let text = "outer:\n  inner: 1"
        text.withCString { src in
            let root = yamlx.parse(src).root
            let nested = "outer".withCString { yamlx.at(root, $0) }   // the { inner: 1 } map
            let m = yamlx.mark(nested)
            #expect(m.ok)
            #expect(m.line == 1)   // the nested map starts on the second line
            #expect(!yamlx.valueSpan(nested, src, Int(text.utf8.count)).endReliable)
        }
    }

    // Line endings & BOM (the pos-skew mitigation in §5). yaml-cpp's stream keeps
    // raw bytes (it does not strip \r), so pos counts \r and CRLF does NOT skew —
    // a plain value still spans reliably. A leading BOM IS consumed during charset
    // detection before pos counting, so it skews every offset; the memcmp gate
    // catches that and fails closed (end withheld, start still reported).
    @Test func handlesLineEndingsAndBOM() {
        // CRLF, value on the second line: no skew, span still reliable + correct.
        let crlf = "a: 1\r\nk: 65\r\n"
        let crlfBytes = Array(crlf.utf8)
        crlf.withCString { src in
            let root = yamlx.parse(src).root
            let s = "k".withCString { yamlx.valueSpan(yamlx.at(root, $0), src, Int(crlfBytes.count)) }
            #expect(s.endReliable, "CRLF should not skew a raw-byte offset")
            #expect(String(decoding: crlfBytes[Int(s.pos) ..< Int(s.end)], as: UTF8.self) == "65")
        }

        // Leading UTF-8 BOM: pos is post-BOM while our bytes include it, so memcmp
        // fails closed — start still valid, end withheld (safe, never a mis-splice).
        let bom = "\u{FEFF}k: 65"
        bom.withCString { src in
            let root = yamlx.parse(src).root
            let s = "k".withCString { yamlx.valueSpan(yamlx.at(root, $0), src, Int(bom.utf8.count)) }
            #expect(s.ok, "start still reported under a BOM skew")
            #expect(!s.endReliable, "BOM skew must fail closed")
        }
    }
}
