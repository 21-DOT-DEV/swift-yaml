import Testing
import YAML
import yamlcppShims

// Key/element removal — `YAMLEditor.unset`. The oracle for every check is an
// independent re-parse through yaml-cpp (`scalarAtPath` / `parses`).
@Suite struct UnsetTests {

    // MARK: Deletion preserves everything else

    /// Deleting a key leaves sibling keys and their comments byte-identical, and
    /// the result re-parses without the key (YAML 1.2.2 Example 2.2).
    @Test func deletingAKeyPreservesSiblingsAndComments() throws {
        let src = """
        hr:  65    # Home runs
        avg: 0.278 # Batting average
        rbi: 147   # Runs Batted In
        """
        let out = try YAMLEditor.unset(src, at: ["avg"])
        #expect(out.contains("hr:  65    # Home runs"))    // sibling verbatim
        #expect(out.contains("rbi: 147   # Runs Batted In"))
        #expect(!out.contains("avg"))
        #expect(!out.contains("Batting average"))          // the deleted line's comment goes with it
        #expect(scalarAtPath(out, ["avg"]) == nil)         // oracle: gone
        #expect(scalarAtPath(out, ["hr"]) == "65")
        #expect(scalarAtPath(out, ["rbi"]) == "147")
    }

    /// A trailing comment on the deleted line goes with it; a comment on the line
    /// above stays (the conservative ownership rule).
    @Test func trailingCommentGoesWithTheLineLeadingStays() throws {
        let src = """
        # a leading note
        port: 8080   # a trailing note
        host: localhost
        """
        let out = try YAMLEditor.unset(src, at: ["port"])
        #expect(out.contains("# a leading note"))          // leading comment kept
        #expect(!out.contains("a trailing note"))           // trailing removed with the line
        #expect(!out.contains("8080"))
        #expect(out.contains("host: localhost"))
    }

    /// Deleting a list item removes its line; later items shift down by one.
    @Test func deletingListItemShiftsIndices() throws {
        let src = """
        features:
          - alpha
          - beta
          - gamma
        """
        let out = try YAMLEditor.unset(src, at: ["features", 0])
        #expect(!out.contains("alpha"))
        #expect(out.contains("- beta"))
        #expect(out.contains("- gamma"))
        #expect(scalarAtPath(out, ["features", 0]) == "beta")   // old index 1 is now 0
    }

    /// Blank lines around the deleted entry are left as-is (not collapsed).
    @Test func blankLinesAreUntouched() throws {
        let out = try YAMLEditor.unset("a: 1\n\nb: 2\n\nc: 3", at: ["b"])
        #expect(out.contains("a: 1\n\n"))    // the blank after `a` survives
        #expect(!out.contains("b: 2"))
        #expect(out.contains("c: 3"))
        #expect(parses(out))
    }

    /// Deleting the sole child of a map leaves an empty parent that re-parses.
    @Test func deletingOnlyEntryStillParses() throws {
        let out = try YAMLEditor.unset("a:\n  only: 1", at: ["a", "only"])
        #expect(scalarAtPath(out, ["a", "only"]) == nil)
        #expect(parses(out))
    }

    /// A quoted value stays deletable (its whole line, quotes and all, is removed).
    @Test func deletingAQuotedValue() throws {
        let out = try YAMLEditor.unset("k: 1\ntls: \"off\"\nh: x", at: ["tls"])
        #expect(!out.contains("tls"))
        #expect(!out.contains("off"))
        #expect(out.contains("k: 1"))
        #expect(out.contains("h: x"))
    }

    /// The compact block sequence's *second* key (on its own line, no `-`) is
    /// deletable, even though its first key isn't (see refusal test below).
    @Test func deletingSecondKeyOfCompactBlockItem() throws {
        let src = """
        features:
          - name: alpha
            port: 8080
        """
        let out = try YAMLEditor.unset(src, at: ["features", 0, "port"])
        #expect(!out.contains("port"))
        #expect(out.contains("- name: alpha"))
        #expect(parses(out))
    }

    /// A quoted key that merely contains a bracket is still deletable (the `[` is
    /// inside quotes, not a flow opener).
    @Test func deletingKeyWhoseNameContainsABracket() throws {
        let out = try YAMLEditor.unset("k: 1\n\"a[b]\": 2", at: ["a[b]"])
        #expect(!out.contains("a[b]"))
        #expect(out.contains("k: 1"))
        #expect(parses(out))
    }

    // MARK: Refused shapes — a typed error, never corruption

    @Test func refusesMissingPath() {
        #expect(throws: YAMLEditError.self) { try YAMLEditor.unset("a: 1", at: ["nope"]) }
    }

    @Test func refusesNestedSection() {
        #expect(throws: YAMLEditError.self) {
            try YAMLEditor.unset("server:\n  port: 8080", at: ["server"])
        }
    }

    @Test func refusesContinuationLineValue() {
        // `key:` then the value on the next line — deleting the value line alone
        // would leave a bare `key:`.
        #expect(throws: YAMLEditError.self) { try YAMLEditor.unset("key:\n  value", at: ["key"]) }
    }

    @Test func refusesCompactBlockSequenceFirstKey() {
        let src = """
        features:
          - name: alpha
            port: 8080
        """
        #expect(throws: YAMLEditError.self) {
            try YAMLEditor.unset(src, at: ["features", 0, "name"])
        }
    }

    @Test func refusesFlowCollectionScalarAndLeavesSourceIntact() throws {
        // The severe case: a scalar inside an inline collection shares its line
        // with the parent key and siblings.
        let src = "features: [alpha, beta]"
        #expect(throws: YAMLEditError.self) { try YAMLEditor.unset(src, at: ["features", 0]) }
        // And a flow mapping value.
        #expect(throws: YAMLEditError.self) {
            try YAMLEditor.unset("config: {host: localhost}", at: ["config", "host"])
        }
    }

    /// A *multi-line* flow collection: the opener `[`/`{` is on an earlier line, so
    /// a line-only scan would miss it and delete a continuation line, stripping the
    /// closing bracket. Depth tracking from the document start catches it.
    @Test func refusesMultiLineFlowCollectionScalar() {
        #expect(throws: YAMLEditError.self) {
            try YAMLEditor.unset("data: [x,\ny, z]", at: ["data", 2])          // z on line 2, [ on line 1
        }
        #expect(throws: YAMLEditError.self) {
            try YAMLEditor.unset("config: {\n  host: x, port: 8080}", at: ["config", "port"])
        }
    }

    // MARK: Line endings

    /// A CRLF (Windows) document: exactly the target line — CR/LF and all — is
    /// removed; the rest is byte-identical.
    @Test func deletesOnlyTheTargetLineInCRLF() throws {
        let out = try YAMLEditor.unset("a: 1\r\nb: 2\r\nc: 3\r\n", at: ["b"])
        #expect(out == "a: 1\r\nc: 3\r\n")
    }

    /// Old-Mac (`\r`-only) endings: yaml-cpp does not treat a lone `\r` as a line
    /// break, so it rejects the document at parse — `unset` throws `malformedDocument`
    /// and never reaches line deletion, so it can never wipe the whole document.
    /// Deterministic (asserts the throw; a regression that let it through and
    /// total-deleted would fail here — unlike a vacuous `if let try?`).
    @Test func crOnlyDocumentIsRejectedAtParseNeverWiped() {
        #expect(throws: YAMLEditError.self) {
            try YAMLEditor.unset("a: 1\rb: 2\rc: 3", at: ["b"])
        }
    }

    @Test func refusesAnchorAliasDocument() {
        #expect(throws: YAMLEditError.self) {
            try YAMLEditor.unset("a: &x 1\nb: *x", at: ["a"])
        }
    }

    // MARK: Oracle helpers — an independent re-parse through yaml-cpp.

    private func parses(_ yaml: String) -> Bool {
        yaml.withCString { yamlx.parse($0).ok }
    }

    private func scalarAtPath(_ yaml: String, _ path: [YAMLPath.Component]) -> String? {
        yaml.withCString { cstr -> String? in
            let r = yamlx.parse(cstr)
            guard r.ok else { return nil }
            var node = r.root
            for component in path {
                switch component {
                case .key(let key):
                    guard Int(yamlx.nodeKind(node)) == 4 else { return nil }
                    var found: yamlx.Node?
                    for i in 0..<Int(yamlx.count(node)) where String(yamlx.mapKeyText(node, i)) == key {
                        found = yamlx.mapValue(node, i)
                        break
                    }
                    guard let child = found else { return nil }
                    node = child
                case .index(let index):
                    guard Int(yamlx.nodeKind(node)) == 3, index < Int(yamlx.count(node)) else { return nil }
                    node = yamlx.seqItem(node, index)
                }
            }
            guard Int(yamlx.nodeKind(node)) == 2 else { return nil }
            return String(yamlx.scalarText(node))
        }
    }
}
