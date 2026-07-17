import Testing
import Foundation
import YAML
import yamlcppShims

// Add-if-absent / fill-a-blank — `YAMLEditor.insert`. The oracle for every check is
// an independent re-parse through yaml-cpp (`scalarAtPath` / `parses`).
@Suite struct InsertTests {

    // MARK: Fill a null value (keeps a same-line trailing comment)

    @Test func fillsBareNull() throws {
        #expect(try YAMLEditor.insert("a:", at: ["a"], to: 1) == "a: 1")
        #expect(scalarAtPath("a:", ["a"]) == nil)                    // was null
    }

    @Test func fillsTildeAndKeywordNull() throws {
        #expect(try YAMLEditor.insert("a: ~", at: ["a"], to: 1) == "a: 1")
        #expect(try YAMLEditor.insert("a: null", at: ["a"], to: 1) == "a: 1")
        #expect(try YAMLEditor.insert("a: NULL", at: ["a"], to: 1) == "a: 1")
    }

    @Test func fillKeepsTrailingComment() throws {
        #expect(try YAMLEditor.insert("a: # fill me", at: ["a"], to: "done") == "a: done # fill me")
        #expect(try YAMLEditor.insert("a: ~ # fill me", at: ["a"], to: "done") == "a: done # fill me")
    }

    /// Whitespace before a trailing comment is preserved (aligned comments survive),
    /// not collapsed to one space — consistent with `set`.
    @Test func fillPreservesMultiSpaceBeforeComment() throws {
        #expect(try YAMLEditor.insert("a:    # note", at: ["a"], to: "x") == "a: x    # note")
        #expect(try YAMLEditor.insert("a: ~   # note", at: ["a"], to: "x") == "a: x   # note")
    }

    @Test func fillInMultiLineDocumentTouchesOnlyItsLine() throws {
        let out = try YAMLEditor.insert("a:\nb: 2", at: ["a"], to: 1)
        #expect(out == "a: 1\nb: 2")
        #expect(scalarAtPath(out, ["a"]) == "1")
        #expect(scalarAtPath(out, ["b"]) == "2")
    }

    @Test func fillNestedNull() throws {
        let out = try YAMLEditor.insert("server:\n  host: x\n  tls:", at: ["server", "tls"], to: true)
        #expect(out == "server:\n  host: x\n  tls: true")
        #expect(scalarAtPath(out, ["server", "tls"]) == "true")
    }

    @Test func fillHonorsNumberVsStringIntent() throws {
        #expect(try YAMLEditor.insert("a:", at: ["a"], to: 2) == "a: 2")               // number → plain
        let quoted = try YAMLEditor.insert("a:", at: ["a"], to: "2")
        #expect(quoted.contains("\"2\"") || quoted.contains("'2'"))                     // string → quoted
        #expect(scalarAtPath(quoted, ["a"]) == "2")
    }

    // MARK: Add a brand-new key (appended at the block's end, sibling indent)

    @Test func addsKeyAtEndOfTopLevelBlock() throws {
        let out = try YAMLEditor.insert("a: 1\nb: 2", at: ["c"], to: 3)
        #expect(out == "a: 1\nb: 2\nc: 3")
        #expect(scalarAtPath(out, ["c"]) == "3")
    }

    /// A CRLF document whose last line lacks a terminator: the separator before the
    /// new key is CRLF too, not a lone LF (no mixed line endings).
    @Test func addsKeyMatchingCRLFAtEndOfFile() throws {
        #expect(try YAMLEditor.insert("a: 1\r\nb: 2", at: ["c"], to: 3) == "a: 1\r\nb: 2\r\nc: 3")
    }

    @Test func addsKeyAtEndOfNestedBlock() throws {
        let out = try YAMLEditor.insert("server:\n  host: x\n  port: 8080", at: ["server", "tls"], to: true)
        #expect(out == "server:\n  host: x\n  port: 8080\n  tls: true")
        #expect(scalarAtPath(out, ["server", "host"]) == "x")       // siblings intact
        #expect(scalarAtPath(out, ["server", "tls"]) == "true")
    }

    /// When the block's last entry is itself a nested block, the new key lands after
    /// the whole subsection (the dedent rule), at the block's indentation.
    @Test func addsAfterAMultiLineLastEntry() throws {
        let out = try YAMLEditor.insert("a:\n  b: 1\n  c:\n    d: 2", at: ["a", "e"], to: 5)
        #expect(out == "a:\n  b: 1\n  c:\n    d: 2\n  e: 5")
        #expect(scalarAtPath(out, ["a", "c", "d"]) == "2")
        #expect(scalarAtPath(out, ["a", "e"]) == "5")
    }

    /// A trailing block-level comment stays at the block's tail; the new key goes
    /// before it (right after the last data line).
    @Test func addsBeforeATrailingComment() throws {
        let out = try YAMLEditor.insert("a:\n  b: 1\n  # trailing note", at: ["a", "c"], to: 2)
        #expect(out == "a:\n  b: 1\n  c: 2\n  # trailing note")
    }

    @Test func addsPreservingSiblingComments() throws {
        let src = "hr:  65    # Home runs\navg: 0.278 # Batting average"
        let out = try YAMLEditor.insert(src, at: ["rbi"], to: 147)
        #expect(out.contains("hr:  65    # Home runs"))              // untouched, verbatim
        #expect(out.contains("avg: 0.278 # Batting average"))
        #expect(out.hasSuffix("\nrbi: 147"))
        #expect(scalarAtPath(out, ["rbi"]) == "147")
    }

    @Test func addsKeyThatNeedsQuoting() throws {
        // `x: y` (colon-*space*) can't be a plain scalar, so it must be quoted; a bare
        // `a:b` (no space) is a valid plain key and is left unquoted.
        let out = try YAMLEditor.insert("a: 1", at: ["x: y"], to: 2)
        #expect(out.contains("\"x: y\"") || out.contains("'x: y'"))
        #expect(scalarAtPath(out, ["x: y"]) == "2")
        #expect(try YAMLEditor.insert("a: 1", at: ["a:b"], to: 2) == "a: 1\na:b: 2")   // no space → bare
        #expect(parses(out))
    }

    // MARK: Add-only — refuse when a real value is already present

    @Test func refusesWhenRealValuePresent() {
        #expect(throws: YAMLEditError.self) { try YAMLEditor.insert("a: 1", at: ["a"], to: 2) }
    }

    @Test func refusesEmptyStringAsRealValue() {
        // An empty string is a value, not a blank — `set`'s job, not `insert`'s.
        #expect(throws: YAMLEditError.self) { try YAMLEditor.insert("a: \"\"", at: ["a"], to: 2) }
        #expect(throws: YAMLEditError.self) { try YAMLEditor.insert("a: ''", at: ["a"], to: 2) }
    }

    // MARK: Refused shapes — a typed error, never corruption

    @Test func refusesMapOrSequenceTarget() {
        #expect(throws: YAMLEditError.self) { try YAMLEditor.insert("a:\n  b: 1", at: ["a"], to: 2) }
    }

    @Test func refusesInlineFlowParent() {
        #expect(throws: YAMLEditError.self) { try YAMLEditor.insert("a: {b: 1}", at: ["a", "c"], to: 2) }
    }

    @Test func refusesListFinalTarget() {
        // Appending to / filling a list position is out of scope this cut.
        #expect(throws: YAMLEditError.self) { try YAMLEditor.insert("a:\n  - 1", at: ["a", 1], to: 2) }
    }

    @Test func refusesMissingOrNonMapParent() {
        #expect(throws: YAMLEditError.self) { try YAMLEditor.insert("a: 1", at: ["x", "y"], to: 2) }   // no `x`
        #expect(throws: YAMLEditError.self) { try YAMLEditor.insert("a: 1", at: ["a", "b"], to: 2) }   // `a` is a scalar
    }

    @Test func refusesAnchorAliasAndMalformed() {
        #expect(throws: YAMLEditError.self) { try YAMLEditor.insert("a: &x 1\nb: *x", at: ["c"], to: 2) }
        #expect(throws: YAMLEditError.self) { try YAMLEditor.insert("a: [1, 2", at: ["c"], to: 2) }
    }

    // MARK: Oracle helpers — an independent re-parse through yaml-cpp.

    private func parses(_ yaml: String) -> Bool { yaml.withCString { yamlx.parse($0).ok } }

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
                        found = yamlx.mapValue(node, i); break
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

// Bump tripwire — pins the yaml-cpp behavior `insert` (and decoding) relies on to
// tell a fillable "no value" from a real empty string. If a future yaml-cpp update
// (e.g. the read-null-as-"null" regression in 0.8.0, jbeder/yaml-cpp#1290) changes
// any of these, these fail loudly and point straight at the cause — before it can
// surface as a silent editing/decoding bug.
@Suite struct EngineNullContract {
    private func valueKind(_ yaml: String) -> Int {
        yaml.withCString { Int(yamlx.nodeKind(yamlx.mapValue(yamlx.parse($0).root, 0))) }
    }

    @Test func noValueSpellingsAreLabelledNull() {
        #expect(valueKind("a:") == 1)          // 1 == null
        #expect(valueKind("a: ~") == 1)
        #expect(valueKind("a: null") == 1)
        #expect(valueKind("a: NULL") == 1)
    }

    @Test func emptyStringIsLabelledScalarNotNull() {
        #expect(valueKind("a: \"\"") == 2)     // 2 == scalar — NOT null (#1290 would break this)
        #expect(valueKind("a: ''") == 2)
    }

    @Test func decodingANoValueYieldsNilNotTheStringNull() throws {
        // #1290's real surface: reading a no-value out as text. On our engine it is
        // nil (absent), not the literal "null".
        struct M: Codable { let a: String? }
        #expect(try YAMLDecoder().decode(M.self, from: "a:").a == nil)
    }
}
