import Testing
import Foundation
import YAML

// Strict duplicate-key rejection — `YAMLDecoder.duplicateKeyStrategy = .reject`.
@Suite struct DuplicateKeyTests {
    private func rejecting() -> YAMLDecoder {
        let d = YAMLDecoder(); d.duplicateKeyStrategy = .reject; return d
    }
    /// The `YAMLError` wrapped inside a rejected decode, or nil if it decoded
    /// (or failed for some other reason). Decoding into `[String: Int]` is enough
    /// because the duplicate scan runs before any type-shaping.
    private func dupError(_ yaml: String) -> YAMLError? {
        do { _ = try rejecting().decode([String: Int].self, from: yaml); return nil }
        catch let DecodingError.dataCorrupted(ctx) { return ctx.underlyingError as? YAMLError }
        catch { return nil }
    }

    // MARK: Rejects — a typed, positioned error, wrapped as DecodingError

    @Test func rejectsTopLevelDuplicateWithPosition() {
        guard case let .duplicateKey(key, line, column)? = dupError("a: 1\na: 2") else {
            Issue.record("expected .duplicateKey"); return
        }
        #expect(key == "a")
        #expect(line == 2)       // 1-based: the second `a` is on line 2
        #expect(column == 1)     // 1-based
    }

    @Test func rejectsNestedDuplicate() {
        guard case let .duplicateKey(key, _, _)? = dupError("a:\n  b: 1\n  b: 2") else {
            Issue.record("expected .duplicateKey"); return
        }
        #expect(key == "b")
    }

    @Test func rejectsInlineFlowDuplicate() {
        guard case let .duplicateKey(key, _, _)? = dupError("{a: 1, a: 2}") else {
            Issue.record("expected .duplicateKey"); return
        }
        #expect(key == "a")
    }

    @Test func rejectsRepeatedMergeKey() {
        guard case let .duplicateKey(key, _, _)? = dupError("base: &b {x: 1}\nm:\n  <<: *b\n  <<: *b") else {
            Issue.record("expected .duplicateKey"); return
        }
        #expect(key == "<<")
    }

    // MARK: Accepts / unchanged

    @Test func acceptsNoDuplicate() throws {
        #expect(try rejecting().decode([String: Int].self, from: "a: 1\nb: 2") == ["a": 1, "b": 2])
    }

    @Test func acceptsSameKeyInDifferentMappings() throws {
        let out = try rejecting().decode([String: [String: Int]].self, from: "a:\n  x: 1\nb:\n  x: 2")
        #expect(out == ["a": ["x": 1], "b": ["x": 2]])
    }

    @Test func acceptsDuplicateConfinedToALaterDocument() throws {
        // Only the first document is checked; the duplicate `b` lives in document 2.
        #expect(try rejecting().decode([String: Int].self, from: "a: 1\n---\nb: 2\nb: 3") == ["a": 1])
    }

    @Test func acceptsDistinctNonScalarKeys() {
        // Two distinct sequence keys aren't scalars, so they fall outside the
        // compared scope (like null/alias keys). `.reject` must not flag them as
        // duplicates merely because the string-keyed overlay collapses both to "".
        if case .duplicateKey? = dupError("? [a, b]\n: 1\n? [c, d]\n: 2") {
            Issue.record("distinct non-scalar keys must not be rejected as duplicates")
        }
    }

    @Test func doesNotRejectRepeatedNullKeys() {
        // Null keys are consumed for parity but not compared (documented scope),
        // so a repeated `~` key is not a rejectable duplicate — it must not be
        // conflated with the empty-string "" bucket into a false positive.
        if case .duplicateKey? = dupError("~: 1\n~: 2") {
            Issue.record("null keys are outside the compared scope; must not reject")
        }
    }

    @Test func acceptsNonScalarKeyThenEmptyScalarKey() {
        // A non-scalar key collapses into the "" bucket; a later genuine "" scalar
        // key then collides with it there. They are different keys, so `.reject`
        // must not throw a false duplicate — empty keys are left to the byte
        // pre-pass, which rejects two "" scalar keys and never inserts non-scalar ones.
        if case .duplicateKey? = dupError("? [a, b]\n: 1\n\"\": 2") {
            Issue.record("a non-scalar key and a distinct empty-scalar key must not be rejected")
        }
    }

    @Test func rejectsRepeatedEmptyScalarKeys() {
        // Two genuine empty-string scalar keys ARE a duplicate — caught by the byte
        // pre-pass (the build net deliberately leaves empty keys to it).
        guard case .duplicateKey? = dupError("\"\": 1\n\"\": 2") else {
            Issue.record("expected .duplicateKey for repeated empty-string scalar keys"); return
        }
    }

    @Test func useFirstKeepsFirstAcrossCollapsedNonScalarKeys() throws {
        // Non-scalar keys are unrepresentable and collapse into the "" bucket;
        // under useFirst the first occurrence wins there, matching useFirst
        // everywhere else. (A per-key scalar gate once regressed this to last-wins.)
        let d = YAMLDecoder(); d.duplicateKeyStrategy = .useFirst
        #expect(try d.decode([String: Int].self, from: "? [a, b]\n: 1\n? [c, d]\n: 2") == ["": 1])
    }

    @Test func otherStrategiesAreUnchangedByReject() throws {
        // Adding `.reject` leaves the resolving strategies alone: the default
        // (useLast) keeps the last value, useFirst keeps the first — neither throws.
        #expect(try YAMLDecoder().decode([String: Int].self, from: "a: 1\na: 2") == ["a": 2])
        let first = YAMLDecoder(); first.duplicateKeyStrategy = .useFirst
        #expect(try first.decode([String: Int].self, from: "a: 1\na: 2") == ["a": 1])
    }

    @Test func rejectionSurfacesAsDecodingError() {
        // A bare YAMLError must not escape `catch DecodingError`.
        #expect(throws: DecodingError.self) {
            try rejecting().decode([String: Int].self, from: "a: 1\na: 2")
        }
    }

    @Test func reportsDuplicateEvenWhenDocumentIsAlsoMalformed() {
        // The duplicate `a` is seen before the parser trips on the unterminated
        // flow sequence. The detector's handler outlives the parse exception, so
        // the recorded duplicate survives stack unwinding and is reported — the
        // trailing syntax error does not mask it.
        guard case let .duplicateKey(key, line, column)? = dupError("a: 1\na: 2\nb: [1, 2") else {
            Issue.record("expected .duplicateKey, not the trailing syntax error"); return
        }
        #expect(key == "a")
        #expect(line == 2)
        #expect(column == 1)
    }

    @Test func rejectsCanonicallyEquivalentKeys() {
        // NFC "é" (U+00E9) and NFD "é" (e + U+0301 combining acute) are
        // byte-distinct but canonically equal, so Swift's Dictionary — and the
        // map this decodes into — treats them as one key. The byte-based pre-pass
        // misses them; the build-time completeness net catches the collapse and
        // rejects, keeping `.reject` consistent with the map it would produce.
        guard case let .duplicateKey(_, line, column)? = dupError("\u{00E9}: 1\ne\u{0301}: 2") else {
            Issue.record("expected .duplicateKey for NFC/NFD-equivalent keys"); return
        }
        // The build-time net reports the second *key*'s position (line 2, col 1),
        // not its value's — matching the byte pre-pass's key-positioned error.
        #expect(line == 2)
        #expect(column == 1)
    }
}
