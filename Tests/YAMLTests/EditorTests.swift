import Testing
import YAML
import yamlcppShims

// Surgical value set — `YAMLEditor.set`. The oracle for every "reads back as
// intended" check is an independent re-parse through yaml-cpp (`scalarAtPath`).
@Suite struct EditorTests {

    static let config = """
    # App config
    server:
      host: localhost     # dev
      port: 8080          # bump me
      tls: "off"          # keep string
    features:
      - alpha
      - beta
    """

    // MARK: Preservation & oracle

    @Test func plainEditChangesOnlyThatValue() throws {
        let out = try YAMLEditor.set(Self.config, at: ["server", "port"], to: 9090)

        // Exactly one line differs, and it's the port line (comment alignment kept
        // because 9090 is the same width as 8080).
        let before = Self.config.split(separator: "\n", omittingEmptySubsequences: false)
        let after = out.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(before.count == after.count)
        #expect(zip(before, after).filter { $0 != $1 }.count == 1)
        #expect(out.contains("port: 9090          # bump me"))
        #expect(!out.contains("8080"))

        // Oracle: re-parse; the value is the intended one.
        #expect(scalarAtPath(out, ["server", "port"]) == "9090")
    }

    @Test func quotedEditStaysAString() throws {
        // `on` is a YAML boolean token, so it must stay quoted to remain a string.
        let out = try YAMLEditor.set(Self.config, at: ["server", "tls"], to: "on")
        #expect(out.contains("tls: \"on\""))
        #expect(!out.contains("off"))
        #expect(scalarAtPath(out, ["server", "tls"]) == "on")
    }

    @Test func numericLookingStringIsQuoted() throws {
        let out = try YAMLEditor.set("v: x", at: ["v"], to: "2")
        #expect(out.contains("\"2\"") || out.contains("'2'"))   // quoted so it stays a string
        #expect(scalarAtPath(out, ["v"]) == "2")
    }

    @Test func numberVsStringIntentIsHonored() throws {
        #expect(try YAMLEditor.set("v: x", at: ["v"], to: 2) == "v: 2")            // number → plain
        #expect(try YAMLEditor.set("v: x", at: ["v"], to: .uint(9_000_000_000)) == "v: 9000000000")
    }

    @Test func listIndexEdit() throws {
        let out = try YAMLEditor.set(Self.config, at: ["features", 0], to: "gamma")
        #expect(out.contains("- gamma"))
        #expect(out.contains("- beta"))
        #expect(!out.contains("- alpha"))
    }

    @Test func settingSameValueIsANoOp() throws {
        #expect(try YAMLEditor.set("k: hello", at: ["k"], to: "hello") == "k: hello")
    }

    // MARK: Quoted-end scan

    @Test func quotedEndScanHonorsEscapes() throws {
        // Double-quoted with an escaped quote inside.
        #expect(scalarAtPath(try YAMLEditor.set(#"k: "a\"b""#, at: ["k"], to: "z"), ["k"]) == "z")
        // Single-quoted with an escaped '' inside.
        #expect(scalarAtPath(try YAMLEditor.set("k: 'a''b'", at: ["k"], to: "z"), ["k"]) == "z")
    }

    // MARK: Flow collections — a *scalar inside* `[…]`/`{…}` is editable
    //
    // `set` overwrites only the scalar's own byte span (unlike `unset`, which
    // deletes the whole line), so siblings and the enclosing brackets survive.
    // These lock the capability the doc advertises; the refusal cases below prove
    // `set` still declines the same shapes (multi-line/null) *inside* flow.

    /// A plain scalar in a flow sequence is replaced in place — the sibling and
    /// the brackets are byte-identical, including when the target abuts `]`.
    @Test func flowSequenceScalarEditsInPlace() throws {
        #expect(try YAMLEditor.set("key: [a, b]", at: ["key", 0], to: "x") == "key: [x, b]")
        #expect(try YAMLEditor.set("key: [a, b]", at: ["key", 1], to: "x") == "key: [a, x]")  // abuts ]
        let out = try YAMLEditor.set("key: [a, b]", at: ["key", 0], to: "x")
        #expect(scalarAtPath(out, ["key", 0]) == "x")   // oracle
        #expect(scalarAtPath(out, ["key", 1]) == "b")
    }

    /// A flow mapping value is replaced in place; the other pair is untouched.
    @Test func flowMappingValueEditsInPlace() throws {
        #expect(try YAMLEditor.set("key: {a: b, c: d}", at: ["key", "c"], to: "x") == "key: {a: b, c: x}")
        let out = try YAMLEditor.set("key: {a: b, c: d}", at: ["key", "a"], to: "x")
        #expect(out == "key: {a: x, c: d}")
        #expect(scalarAtPath(out, ["key", "a"]) == "x")
        #expect(scalarAtPath(out, ["key", "c"]) == "d")
    }

    /// A quoted scalar inside a flow collection is spanned (quotes and all) and
    /// replaced; the neighbor stays verbatim.
    @Test func flowQuotedScalarEdits() throws {
        let out = try YAMLEditor.set("key: [\"a\", b]", at: ["key", 0], to: "z")
        #expect(out == "key: [z, b]")
        #expect(scalarAtPath(out, ["key", 0]) == "z")
    }

    /// A nested flow collection resolves through both levels to the leaf scalar.
    @Test func flowNestedScalarEdits() throws {
        #expect(try YAMLEditor.set("key: [[a, b], c]", at: ["key", 0, 1], to: "x") == "key: [[a, x], c]")
    }

    /// Quote-as-needed still applies inside flow: a numeric-looking string is
    /// quoted so it reads back as a string, not a number.
    @Test func flowNumericStringStaysQuoted() throws {
        let out = try YAMLEditor.set("key: [a, b]", at: ["key", 0], to: "2")
        #expect(out == "key: [\"2\", b]")
        #expect(scalarAtPath(out, ["key", 0]) == "2")   // string, via the re-parse oracle
    }

    /// A flow collection may span lines (opener on an earlier line); editing a
    /// scalar on a continuation line touches only that scalar.
    @Test func flowSpanningMultipleLinesEdits() throws {
        #expect(try YAMLEditor.set("key: [a,\n  b]", at: ["key", 1], to: "x") == "key: [a,\n  x]")
    }

    /// Refusal parity: a null element inside flow is still `unsupportedValueShape`
    /// (there is no scalar span to overwrite) — flow doesn't relax the shape rules.
    @Test func flowNullElementIsUnsupported() {
        #expect(throws: YAMLEditError.self) {
            try YAMLEditor.set("key: [~, b]", at: ["key", 0], to: "x")
        }
    }

    /// Refusal parity: a *multi-line* quoted scalar inside flow is refused, same
    /// as anywhere — the single-line quoted-end scan defers on the line break.
    @Test func flowMultiLineQuotedScalarIsUnsupported() {
        #expect(throws: YAMLEditError.self) {
            try YAMLEditor.set("key: [\"a\nb\", c]", at: ["key", 0], to: "z")
        }
    }

    // MARK: Errors

    @Test func missingKeyThrows() {
        #expect(throws: YAMLEditError.self) {
            try YAMLEditor.set(Self.config, at: ["server", "nope"], to: 1)
        }
    }

    @Test func indexOutOfRangeThrows() {
        #expect(throws: YAMLEditError.self) {
            try YAMLEditor.set(Self.config, at: ["features", 9], to: 1)
        }
    }

    @Test func wholeMapTargetThrows() {
        #expect(throws: YAMLEditError.self) {
            try YAMLEditor.set(Self.config, at: ["server"], to: 1)
        }
    }

    @Test func blockScalarTargetIsUnsupported() {
        #expect(throws: YAMLEditError.self) {
            try YAMLEditor.set("k: |\n  line one\n  line two", at: ["k"], to: "z")
        }
    }

    @Test func anchorAliasDocumentIsRefused() {
        #expect(throws: YAMLEditError.self) {
            try YAMLEditor.set("a: &x 1\nb: *x", at: ["a"], to: 2)
        }
    }

    @Test func tagPrecededAnchorIsStillRefused() {
        // The scan must skip the tag before flagging the anchor.
        #expect(throws: YAMLEditError.self) {
            try YAMLEditor.set("a: !!str &x hi\nb: *x", at: ["a"], to: "z")
        }
    }

    @Test func malformedInputThrows() {
        #expect(throws: YAMLEditError.self) {
            try YAMLEditor.set("a: [1, 2", at: ["a"], to: 1)   // unterminated flow
        }
    }

    // MARK: The scan does NOT over-refuse ordinary `&`/`*` in scalars

    @Test func ampersandInsideAStringIsNotAnAnchor() throws {
        let src = "url: http://a&b\nname: cats & dogs"
        let out = try YAMLEditor.set(src, at: ["url"], to: "http://c&d")
        #expect(scalarAtPath(out, ["url"]) == "http://c&d")
        #expect(scalarAtPath(out, ["name"]) == "cats & dogs")
    }

    @Test func asteriskInsideAStringIsNotAnAlias() throws {
        let out = try YAMLEditor.set("expr: 5 * 3", at: ["expr"], to: "6 * 7")
        #expect(scalarAtPath(out, ["expr"]) == "6 * 7")
    }

    // MARK: Spec-derived (YAML 1.2.2 numbered examples, yaml.org/spec/1.2.2)
    //
    // The authoritative corpus the wrap's smoke tests already cite. Lifted
    // verbatim — 2.17 as a raw string so its backslash escapes stay literal.

    /// Example 2.2 — Mapping Scalars to Scalars (with trailing comments).
    static let example22 = """
    hr:  65    # Home runs
    avg: 0.278 # Batting average
    rbi: 147   # Runs Batted In
    """

    /// Example 2.10 — a node ("Sammy Sosa") anchored (`&SS`) and aliased (`*SS`).
    static let example210 = """
    ---
    hr:
    - Mark McGwire
    # Following node labeled SS
    - &SS Sammy Sosa
    rbi:
    - *SS # Subsequent occurrence
    - Ken Griffey
    """

    /// Example 2.17 — Quoted Scalars (single/double, with escapes).
    static let example217 = #"""
    unicode: "Sosa did fine.☺"
    control: "\b1998\t1999\t2000\n"
    hex esc: "\x0d\x0a is \r\n"

    single: '"Howdy!" he cried.'
    quoted: ' # Not a ''comment''.'
    tie-fighter: '|\-*-/|'
    """#

    /// The core promise on spec-canonical input: editing one value leaves every
    /// comment byte-identical (Example 2.2). `0.278` → `0.301` keeps the column.
    @Test func spec22_editPreservesEveryComment() throws {
        let out = try YAMLEditor.set(Self.example22, at: ["avg"], to: 0.301)
        #expect(out.contains("hr:  65    # Home runs"))          // untouched, verbatim
        #expect(out.contains("avg: 0.301 # Batting average"))     // edited value, comment kept
        #expect(out.contains("rbi: 147   # Runs Batted In"))      // untouched, verbatim
        #expect(scalarAtPath(out, ["avg"]) == "0.301")            // oracle
    }

    /// A spec-canonical anchored/aliased document (Example 2.10) is refused —
    /// yaml-cpp collapses the alias onto its anchor, so it can't be spliced safely.
    @Test func spec210_anchorAliasDocumentIsRefused() {
        #expect(throws: YAMLEditError.self) {
            try YAMLEditor.set(Self.example210, at: ["hr", 0], to: "x")
        }
    }

    /// The quoted-end scan spans a single-quoted value that *contains a double
    /// quote* (Example 2.17, `single`), replacing only it.
    @Test func spec217_editSingleQuotedWithEmbeddedDoubleQuote() throws {
        let out = try YAMLEditor.set(Self.example217, at: ["single"], to: "hi")
        #expect(scalarAtPath(out, ["single"]) == "hi")
        #expect(out.contains(#"tie-fighter: '|\-*-/|'"#))       // neighbor verbatim
        #expect(out.contains(#"unicode: "Sosa did fine.☺""#)) // neighbor verbatim
    }

    /// The single-quote scan honors the `''` escape and does *not* mistake the
    /// inner `#` for a comment (Example 2.17, `quoted: ' # Not a ''comment''.'`).
    @Test func spec217_editSingleQuotedWithEscapedQuotesAndHash() throws {
        let out = try YAMLEditor.set(Self.example217, at: ["quoted"], to: "plain")
        #expect(scalarAtPath(out, ["quoted"]) == "plain")
        #expect(!out.contains("Not a"))                            // the whole token replaced
        #expect(out.contains(#"single: '"Howdy!" he cried.'"#))   // neighbor verbatim
    }

    /// A double-quoted value with backslash escapes (Example 2.17, `control:
    /// "\b1998\t1999\t2000\n"`) is spanned across every `\`-escape to its closing
    /// quote and replaced — exercising the double-quote scan's escape-skip.
    @Test func spec217_editDoubleQuotedWithEscapes() throws {
        let out = try YAMLEditor.set(Self.example217, at: ["control"], to: "plain")
        #expect(scalarAtPath(out, ["control"]) == "plain")
        #expect(out.contains(#"hex esc: "\x0d\x0a is \r\n""#))     // neighbor verbatim
    }

    // MARK: Oracle helper — an independent re-parse through yaml-cpp.

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
