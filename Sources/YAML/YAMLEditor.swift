import yamlcppShims

/// Surgical, comment-preserving edits to YAML text: change a scalar value in
/// place (``set(_:at:to:)``) or delete a leaf entry (``unset(_:at:)``), leaving
/// comments, blank lines, key order, indentation, and quoting everywhere else
/// byte-for-byte identical — the textual diff covers only the edited value or the
/// removed line. It never re-emits the whole document (which would reformat and
/// drop comments); it locates the exact source span and splices/removes in place.
///
/// See `Specs/002-surgical-value-set/plan.md` (set) and
/// `Specs/003-key-removal-unset/plan.md` (unset) for the design and review history.
public enum YAMLEditor {

    /// The replacement handed to ``set(_:at:to:)``. Scalar-only — you cannot set
    /// a value to a whole map or sequence. Literals give `int`/`double`/`string`/
    /// `bool`/`null`; `.uint` / `.float` are reachable explicitly for values
    /// beyond `Int` range or 32-bit precision. The library quotes it as needed so
    /// the edit reads back as the type you meant (`"2"` stays a string, `2` a
    /// number).
    public enum Value: Sendable,
        ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
        ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral, ExpressibleByNilLiteral
    {
        case string(String)
        case int(Int)
        case uint(UInt64)
        case double(Double)
        case float(Float)
        case bool(Bool)
        case null

        public init(stringLiteral value: String) { self = .string(value) }
        public init(integerLiteral value: Int) { self = .int(value) }
        public init(floatLiteral value: Double) { self = .double(value) }
        public init(booleanLiteral value: Bool) { self = .bool(value) }
        public init(nilLiteral: ()) { self = .null }

        /// Lower to the internal serializer model (`YAMLValue.int` is `Int64`).
        var storage: YAMLValue {
            switch self {
            case .string(let s): return .string(s)
            case .int(let i): return .int(Int64(i))
            case .uint(let u): return .uint(u)
            case .double(let d): return .double(d)
            case .float(let f): return .float(f)
            case .bool(let b): return .bool(b)
            case .null: return .null
            }
        }
    }

    /// Changes the value at `path` to `value` in `yaml`, returning the edited
    /// text. Everything outside the edited value stays byte-identical. The target
    /// may be a plain or single-line-quoted scalar anywhere it appears —
    /// including one *inside* a flow collection (`[a, b]` / `{a: b}`), where only
    /// the scalar's own bytes are rewritten, leaving its siblings and the
    /// enclosing brackets untouched.
    ///
    /// - Throws: ``YAMLEditError`` — a malformed document, an anchor/alias
    ///   document (which cannot be edited safely), a path that does not resolve,
    ///   a map/sequence target (not a single value), or a scalar whose shape this
    ///   version does not edit yet — a multi-line, block (`|`/`>`), or empty/null
    ///   value; see ``YAMLEditError/unsupportedValueShape(path:)`` for the full
    ///   list. Unlike ``unset(_:at:)``, a scalar inside a flow collection is
    ///   *not* refused: `set` overwrites only the scalar's span, whereas `unset`
    ///   would delete the whole line and wipe the collection.
    public static func set(_ yaml: String, at path: [YAMLPath.Component], to value: Value) throws -> String {
        let (bytes, valueStart, valueEnd) = try locateSingleLineScalar(yaml, at: path)
        // Serialize the replacement (no trailing newline) and splice it in place.
        let token = YAMLSerialization.emitScalarToken(value.storage)
        let spliced = bytes[0..<valueStart] + Array(token.utf8) + bytes[valueEnd...]
        return String(decoding: spliced, as: UTF8.self)
    }

    /// Parses `yaml`, walks `path` to the target, and confirms it is a single-line
    /// scalar — returning the source bytes and the value's byte range `[start, end)`.
    /// Shared by `set` (which overwrites the range) and `unset` (which removes the
    /// line the range's start sits on). Throws the shared `YAMLEditError`s:
    /// `malformedDocument`, `documentUsesAnchorsOrAliases`, `pathNotFound`,
    /// `notASingleValue`, `unsupportedValueShape`.
    fileprivate static func locateSingleLineScalar(
        _ yaml: String, at path: [YAMLPath.Component]
    ) throws -> (bytes: [UInt8], valueStart: Int, valueEnd: Int) {
        let bytes = Array(yaml.utf8)

        // Refuse anchor/alias documents — yaml-cpp collapses an alias onto its
        // anchor, so an alias target would silently splice the anchor value.
        if documentUsesAnchorsOrAliases(bytes) {
            throw YAMLEditError.documentUsesAnchorsOrAliases
        }

        return try yaml.withCString { cstr in
            // Parse, guarded.
            let result = yamlx.parse(cstr)
            guard result.ok else {
                throw YAMLEditError.malformedDocument(
                    .parse(message: String(yamlx.parseMessage(result)),
                           line: Int(result.line) + 1,
                           column: Int(result.column) + 1))
            }

            // Navigate, validating each step — never index an undefined node.
            var node = result.root
            var trail: [YAMLPath.Component] = []
            for component in path {
                trail.append(component)
                switch component {
                case .key(let key):
                    guard kind(node) == kindMap, let child = mapChild(node, key: key) else {
                        throw YAMLEditError.pathNotFound(path: trail)
                    }
                    node = child
                case .index(let index):
                    guard kind(node) == kindSequence, index >= 0, index < Int(yamlx.count(node)) else {
                        throw YAMLEditError.pathNotFound(path: trail)
                    }
                    node = yamlx.seqItem(node, index)
                }
                guard kind(node) != kindUndefined else {
                    throw YAMLEditError.pathNotFound(path: trail)
                }
            }

            // Classify: only a scalar target proceeds.
            switch kind(node) {
            case kindScalar: break
            case kindSequence, kindMap: throw YAMLEditError.notASingleValue(path: path)
            default: throw YAMLEditError.unsupportedValueShape(path: path)   // null / undefined
            }

            // The single-line value span: `valueSpan` gives a reliable end for a
            // plain single-line scalar; a quoted scalar's end we scan for here.
            let span = yamlx.valueSpan(node, cstr, Int(bytes.count))
            guard span.ok, span.pos >= 0 else {
                throw YAMLEditError.unsupportedValueShape(path: path)
            }
            let pos = Int(span.pos)
            let end: Int
            if span.endReliable {
                end = Int(span.end)
            } else if pos < bytes.count, bytes[pos] == quoteDouble {
                guard let e = doubleQuotedEnd(bytes, from: pos) else {
                    throw YAMLEditError.unsupportedValueShape(path: path)
                }
                end = e
            } else if pos < bytes.count, bytes[pos] == quoteSingle {
                guard let e = singleQuotedEnd(bytes, from: pos) else {
                    throw YAMLEditError.unsupportedValueShape(path: path)
                }
                end = e
            } else {
                throw YAMLEditError.unsupportedValueShape(path: path)
            }
            return (bytes, pos, end)
        }
    }

    // MARK: - Navigation

    private static func kind(_ node: yamlx.Node) -> Int { Int(yamlx.nodeKind(node)) }

    /// The map value for `key`, or nil if absent. `mapKeyText` uses a thread-local
    /// buffer, so each key is converted to `String` before the next call.
    private static func mapChild(_ node: yamlx.Node, key: String) -> yamlx.Node? {
        let count = Int(yamlx.count(node))
        for i in 0..<count where String(yamlx.mapKeyText(node, i)) == key {
            return yamlx.mapValue(node, i)
        }
        return nil
    }

    // MARK: - Quoted-value end scans (single-line only; every read bounds-checked)

    /// End (exclusive) of a double-quoted scalar opening at `pos`, honoring `\"`
    /// escapes. `nil` if it is unterminated or spans a line break (defer those).
    private static func doubleQuotedEnd(_ bytes: [UInt8], from pos: Int) -> Int? {
        let n = bytes.count
        var i = pos + 1
        while i < n {
            let b = bytes[i]
            if b == backslash { i += 2; continue }          // skip the escaped char
            if b == quoteDouble { return i + 1 }
            if b == newline { return nil }
            i += 1
        }
        return nil
    }

    /// End (exclusive) of a single-quoted scalar opening at `pos`, honoring the
    /// `''` escape. `nil` if unterminated or multi-line.
    private static func singleQuotedEnd(_ bytes: [UInt8], from pos: Int) -> Int? {
        let n = bytes.count
        var i = pos + 1
        while i < n {
            if bytes[i] == quoteSingle {
                if i + 1 < n && bytes[i + 1] == quoteSingle { i += 2; continue }   // escaped ''
                return i + 1
            }
            if bytes[i] == newline { return nil }
            i += 1
        }
        return nil
    }

    // MARK: - Anchor / alias document scan

    /// True if the document uses an anchor (`&name`) or alias (`*name`) at a node
    /// position. Quote/comment-aware and conservative — it flags a `&`/`*` that
    /// *begins* a node's content (optionally after a tag), never one sitting
    /// inside a plain scalar (a URL's `a&b`, "cats & dogs", "5 * 3"). It may
    /// over-flag inside block-scalar bodies, which is safe (we refuse, not
    /// mis-edit). The tag-skip is what keeps `!t &a` from slipping through.
    private static func documentUsesAnchorsOrAliases(_ bytes: [UInt8]) -> Bool {
        let n = bytes.count
        var i = 0
        var expecting = true    // a node's content may begin at this position

        while i < n {
            let b = bytes[i]

            if b == newline { expecting = true; i += 1; continue }
            if b == space || b == tab { i += 1; continue }   // whitespace: no state change

            // Comment: '#' at a token boundary → to end of line.
            if b == hash, i == 0 || bytes[i - 1] == space || bytes[i - 1] == tab || bytes[i - 1] == newline {
                while i < n && bytes[i] != newline { i += 1 }
                continue
            }

            // A quoted scalar is node content; skip over it.
            if b == quoteSingle {
                expecting = false
                i += 1
                while i < n {
                    if bytes[i] == quoteSingle {
                        if i + 1 < n && bytes[i + 1] == quoteSingle { i += 2; continue }
                        i += 1; break
                    }
                    i += 1
                }
                continue
            }
            if b == quoteDouble {
                expecting = false
                i += 1
                while i < n {
                    if bytes[i] == backslash { i += 2; continue }
                    if bytes[i] == quoteDouble { i += 1; break }
                    i += 1
                }
                continue
            }

            if expecting {
                if b == bang {          // a tag; the node content still follows it
                    while i < n && bytes[i] != space && bytes[i] != tab && bytes[i] != newline { i += 1 }
                    continue            // stay `expecting`
                }
                if b == amp || b == star { return true }   // anchor / alias
                expecting = false       // ordinary node content begins here
            }

            // Indicators that open a *following* node position.
            switch b {
            case colon:
                let next = i + 1 < n ? bytes[i + 1] : newline
                if next == space || next == tab || next == newline
                    || next == comma || next == bracketOpen || next == braceOpen { expecting = true }
            case dash:
                let next = i + 1 < n ? bytes[i + 1] : newline
                if next == space || next == tab || next == newline { expecting = true }
            case comma, bracketOpen, braceOpen:
                expecting = true
            default:
                break
            }
            i += 1
        }
        return false
    }

    // MARK: - Constants

    private static let kindUndefined = 0, kindNull = 1, kindScalar = 2, kindSequence = 3, kindMap = 4
    private static let quoteSingle = UInt8(ascii: "'"), quoteDouble = UInt8(ascii: "\"")
    private static let backslash = UInt8(ascii: "\\"), newline = UInt8(ascii: "\n")
    private static let space = UInt8(ascii: " "), tab = UInt8(ascii: "\t")
    private static let hash = UInt8(ascii: "#"), bang = UInt8(ascii: "!")
    private static let amp = UInt8(ascii: "&"), star = UInt8(ascii: "*")
    private static let colon = UInt8(ascii: ":"), dash = UInt8(ascii: "-"), comma = UInt8(ascii: ",")
    private static let bracketOpen = UInt8(ascii: "["), braceOpen = UInt8(ascii: "{")
    private static let bracketClose = UInt8(ascii: "]"), braceClose = UInt8(ascii: "}")
    private static let carriageReturn = UInt8(ascii: "\r")
}

// MARK: - Deletion (unset)

extension YAMLEditor {
    /// Deletes the leaf entry at `path` (a map key or a list item) from `yaml`,
    /// returning the edited text. The entry's whole line — key/`-`, value, and any
    /// trailing same-line comment — is removed; everything else is byte-identical.
    /// Deleting a list item shifts later items' positions down by one.
    ///
    /// - Throws: ``YAMLEditError`` — a malformed or anchor/alias document, a path
    ///   that does not resolve, a map/sequence target, or a shape this version
    ///   cannot remove by whole-line deletion: a value on a continuation line, a
    ///   key sharing a `-` marker's line (compact block sequence), a scalar inside
    ///   an inline `[…]`/`{…}` collection, or a multi-line/empty value.
    public static func unset(_ yaml: String, at path: [YAMLPath.Component]) throws -> String {
        // Reuse the shared locate: parse, walk, confirm a single-line scalar.
        let (bytes, pos, _) = try locateSingleLineScalar(yaml, at: path)
        let n = bytes.count

        // Line start: the byte after the previous line break (LF, CR, or CRLF's LF).
        var lineStart = pos
        while lineStart > 0 && bytes[lineStart - 1] != newline && bytes[lineStart - 1] != carriageReturn {
            lineStart -= 1
        }

        // A whole-line delete is safe only when the target's entry is the sole
        // structural thing on its line. Three guards enforce that:

        // (a) Same-line entry: the value's line must carry the key/`-` before the
        //     value. If it's all whitespace, the value is on a continuation line
        //     separate from its marker (`key:` / `-` above), so deleting this line
        //     would leave a bare `key:`/`-`.
        guard bytes[lineStart..<pos].contains(where: { $0 != space && $0 != tab }) else {
            throw YAMLEditError.unsupportedValueShape(path: path)
        }

        // (b) Enclosing marker: the line may carry at most the target's own block
        //     marker — one leading `- ` for a list index, none for a map key. A
        //     compact `- name: alpha` (deleting `name`) or nested `- - alpha`
        //     carries an enclosing `-` that a line delete would drop.
        var allowedMarkers = 0
        if let last = path.last, case .index = last { allowedMarkers = 1 }
        if leadingBlockMarkerCount(bytes, from: lineStart, to: pos) > allowedMarkers {
            throw YAMLEditError.unsupportedValueShape(path: path)
        }

        // (c) Flow context: a scalar inside an inline `[…]`/`{…}` collection shares
        //     its line with the parent key and siblings; deleting the line would
        //     wipe the whole collection. The opener may be on an *earlier* line
        //     (flow collections span lines), so we track bracket depth from the
        //     document start, not just this line.
        if isInsideFlowCollection(bytes, upTo: pos) {
            throw YAMLEditError.unsupportedValueShape(path: path)
        }

        // Line end: through the next line break, whatever its style (LF / CRLF / CR).
        var lineEnd = pos
        while lineEnd < n && bytes[lineEnd] != newline && bytes[lineEnd] != carriageReturn { lineEnd += 1 }
        if lineEnd < n {
            if bytes[lineEnd] == carriageReturn {
                lineEnd += 1
                if lineEnd < n && bytes[lineEnd] == newline { lineEnd += 1 }   // CRLF
            } else {
                lineEnd += 1   // LF
            }
        }

        return String(decoding: bytes[0..<lineStart] + bytes[lineEnd...], as: UTF8.self)
    }

    /// Number of leading block-sequence markers (`- ` = dash + space/tab) on the
    /// target's line, before the key/scalar begins. A `-` *inside* a key (quoted
    /// `"a - b"` or plain `a - b`) is content, past the leading run, so it isn't
    /// counted — YAML indicators are literal inside a scalar.
    private static func leadingBlockMarkerCount(_ bytes: [UInt8], from lineStart: Int, to pos: Int) -> Int {
        var i = lineStart
        var count = 0
        while i < pos && (bytes[i] == space || bytes[i] == tab) { i += 1 }   // indent
        while i + 1 < pos && bytes[i] == dash && (bytes[i + 1] == space || bytes[i + 1] == tab) {
            count += 1
            i += 2
            while i < pos && (bytes[i] == space || bytes[i] == tab) { i += 1 }
        }
        return count
    }

    /// True if the target at `pos` sits inside an *unclosed* flow collection —
    /// flow-bracket depth is positive at `pos`. Scans from the document start,
    /// because a flow opener can be on an earlier line (flow collections span
    /// lines: `data: [a,\nb, c]`). Quote- and comment-aware, so brackets inside
    /// strings or comments don't count, and a balanced `[…]` before the target
    /// (depth back to 0) or a `[` inside a quoted key (`"a[b]"`) isn't flagged.
    ///
    /// Known limitation (safe / fail-closed): a *block scalar* (`|`/`>`) body is not
    /// skipped, so an unbalanced `[`/`{` in a sibling block scalar *before* the
    /// target would inflate the depth and wrongly refuse an otherwise-valid deletion.
    /// It's a refusal, never corruption, and rare (block-scalar content usually has
    /// balanced or no brackets). A future robustness pass could detect flow context
    /// from yaml-cpp's collection `Style()` (via a small shim) instead of scanning
    /// bytes, retiring this edge and the line-only/multi-line fragility both.
    private static func isInsideFlowCollection(_ bytes: [UInt8], upTo pos: Int) -> Bool {
        var depth = 0
        var i = 0
        while i < pos {
            let b = bytes[i]
            if b == quoteSingle {
                i += 1
                while i < pos {
                    if bytes[i] == quoteSingle {
                        if i + 1 < pos && bytes[i + 1] == quoteSingle { i += 2; continue }
                        i += 1; break
                    }
                    i += 1
                }
                continue
            }
            if b == quoteDouble {
                i += 1
                while i < pos {
                    if bytes[i] == backslash { i += 2; continue }
                    if bytes[i] == quoteDouble { i += 1; break }
                    i += 1
                }
                continue
            }
            // A '#' at a token boundary is a comment to end of line — its brackets
            // are not structural.
            if b == hash, i == 0 || bytes[i - 1] == space || bytes[i - 1] == tab
                || bytes[i - 1] == newline || bytes[i - 1] == carriageReturn {
                while i < pos && bytes[i] != newline && bytes[i] != carriageReturn { i += 1 }
                continue
            }
            if b == bracketOpen || b == braceOpen {
                depth += 1
            } else if b == bracketClose || b == braceClose {
                if depth > 0 { depth -= 1 }
            }
            i += 1
        }
        return depth > 0
    }
}

// MARK: - Insertion (insert)

extension YAMLEditor {
    /// Writes `value` at `path` when it isn't there yet — either **fills** a value
    /// that is currently YAML null (a key with nothing after it, `~`, or `null`), or
    /// **adds** a brand-new key by appending one line at the end of its block, at the
    /// siblings' indentation. Everything else stays byte-for-byte identical, and a
    /// same-line trailing comment on a filled value is kept.
    ///
    /// Add-only: if a real value already sits at `path` (an empty string `""` counts),
    /// it throws ``YAMLEditError/valueAlreadyPresent(path:)`` — use ``set(_:at:to:)``
    /// to change a value that is already there.
    ///
    /// - Throws: ``YAMLEditError`` — a malformed or anchor/alias document; a real value
    ///   already present; or a shape this version cannot add into: a list position
    ///   (appending to a sequence is deferred), a parent that does not resolve
    ///   (`pathNotFound`), a parent that is an inline `{…}` map / a list / a scalar
    ///   (`unsupportedValueShape`), or a target that is itself a map or sequence.
    public static func insert(_ yaml: String, at path: [YAMLPath.Component], to value: Value) throws -> String {
        let bytes = Array(yaml.utf8)
        if documentUsesAnchorsOrAliases(bytes) { throw YAMLEditError.documentUsesAnchorsOrAliases }

        // The target must be a map key; a bare list position is out of scope.
        guard let last = path.last, case .key(let newKey) = last else {
            throw YAMLEditError.unsupportedValueShape(path: path)
        }

        return try yaml.withCString { cstr in
            let result = yamlx.parse(cstr)
            guard result.ok else {
                throw YAMLEditError.malformedDocument(
                    .parse(message: String(yamlx.parseMessage(result)),
                           line: Int(result.line) + 1, column: Int(result.column) + 1))
            }

            // Navigate to the parent (all but the last component), validating each step.
            var node = result.root
            var trail: [YAMLPath.Component] = []
            for component in path.dropLast() {
                trail.append(component)
                switch component {
                case .key(let key):
                    guard kind(node) == kindMap, let child = mapChild(node, key: key) else {
                        throw YAMLEditError.pathNotFound(path: trail)
                    }
                    node = child
                case .index(let index):
                    guard kind(node) == kindSequence, index >= 0, index < Int(yamlx.count(node)) else {
                        throw YAMLEditError.pathNotFound(path: trail)
                    }
                    node = yamlx.seqItem(node, index)
                }
                guard kind(node) != kindUndefined else { throw YAMLEditError.pathNotFound(path: trail) }
            }
            let parent = node

            // The parent must be a *block* map. A missing parent already threw above.
            guard kind(parent) == kindMap else { throw YAMLEditError.unsupportedValueShape(path: path) }
            let pMark = yamlx.mark(parent)
            guard pMark.ok, pMark.pos >= 0, Int(pMark.pos) < bytes.count else {
                throw YAMLEditError.unsupportedValueShape(path: path)
            }
            // A block map's mark points at its first key; a flow map's points at `{`.
            if bytes[Int(pMark.pos)] == braceOpen { throw YAMLEditError.unsupportedValueShape(path: path) }

            let valueToken = YAMLSerialization.emitScalarToken(value.storage)
            if let existing = mapChild(parent, key: newKey) {
                switch kind(existing) {
                case kindNull:   return try fillNullValue(bytes, existing, valueToken, path)
                case kindScalar: throw YAMLEditError.valueAlreadyPresent(path: path)   // includes ""
                default:         throw YAMLEditError.notASingleValue(path: path)
                }
            } else {
                let keyToken = YAMLSerialization.emitScalarToken(.string(newKey))
                return try appendKey(bytes, firstChildAt: Int(pMark.pos), keyToken: keyToken, valueToken: valueToken, path: path)
            }
        }
    }

    /// Fills a null value's slot on its own line with `valueToken`, keeping any
    /// same-line trailing comment. The null's node mark is unreliable for this — for a
    /// bare `key:` it lands on the *next* line — so the key's line is found by scanning
    /// back from the mark to the nearest content, then its value slot is rewritten.
    private static func fillNullValue(_ bytes: [UInt8], _ valueNode: yamlx.Node, _ valueToken: String, _ path: [YAMLPath.Component]) throws -> String {
        let n = bytes.count
        let m = yamlx.mark(valueNode)
        guard m.ok, m.pos >= 0 else { throw YAMLEditError.unsupportedValueShape(path: path) }

        // Back up over whitespace/newlines to land on the key's line.
        var j = min(Int(m.pos), n) - 1
        while j >= 0 && (bytes[j] == space || bytes[j] == tab || bytes[j] == newline || bytes[j] == carriageReturn) { j -= 1 }
        guard j >= 0 else { throw YAMLEditError.unsupportedValueShape(path: path) }
        var lineStart = j
        while lineStart > 0 && bytes[lineStart - 1] != newline && bytes[lineStart - 1] != carriageReturn { lineStart -= 1 }
        var lineEnd = j
        while lineEnd < n && bytes[lineEnd] != newline && bytes[lineEnd] != carriageReturn { lineEnd += 1 }
        guard let colon = keyValueColon(bytes, lineStart, lineEnd) else {
            throw YAMLEditError.unsupportedValueShape(path: path)
        }

        // A trailing comment (`#` at a token boundary) after the value slot.
        var commentStart: Int? = nil
        var i = colon + 1
        while i < lineEnd {
            if bytes[i] == hash && (bytes[i - 1] == space || bytes[i - 1] == tab) { commentStart = i; break }
            i += 1
        }

        // Rebuild the line: `<indent>key: <value>[ <comment>]`, replacing whatever
        // null spelling (nothing / `~` / `null`) sat in the value slot.
        var line = Array(bytes[lineStart...colon])
        line.append(space)
        line.append(contentsOf: valueToken.utf8)
        if let cs = commentStart {
            // Keep the whitespace that preceded the comment (aligned comments
            // survive) — as `set` leaves the bytes after a value untouched. Back up
            // over that run (never past the value's own separator) and re-emit it.
            var gapStart = cs
            while gapStart > colon + 1 && (bytes[gapStart - 1] == space || bytes[gapStart - 1] == tab) { gapStart -= 1 }
            line.append(contentsOf: bytes[gapStart..<lineEnd])
        }
        return String(decoding: bytes[0..<lineStart] + line + bytes[lineEnd...], as: UTF8.self)
    }

    /// Appends `<indent>key: value` at the end of the block whose first child key is
    /// at `firstChildAt`, after the block's last data line (before any trailing
    /// block-level comment or blank), at the siblings' indentation.
    private static func appendKey(_ bytes: [UInt8], firstChildAt: Int, keyToken: String, valueToken: String, path: [YAMLPath.Component]) throws -> String {
        let n = bytes.count
        // The parent's mark points at its first child key; its line gives the
        // children's indentation.
        var firstLineStart = firstChildAt
        while firstLineStart > 0 && bytes[firstLineStart - 1] != newline && bytes[firstLineStart - 1] != carriageReturn { firstLineStart -= 1 }
        let childIndent = Array(bytes[firstLineStart..<firstChildAt])
        guard childIndent.allSatisfy({ $0 == space || $0 == tab }) else {
            throw YAMLEditError.unsupportedValueShape(path: path)
        }
        let childCol = childIndent.count

        // Walk the block to the dedent (a non-blank line indented less than the
        // children). Track the end of the last *data* line: a deeper (nested) line, or
        // a sibling key at the child indent — skipping blanks and a trailing
        // block-level comment (a `#` sitting at the child indent).
        var anchorEnd = -1
        var ls = firstLineStart
        while ls < n {
            var le = ls
            while le < n && bytes[le] != newline && bytes[le] != carriageReturn { le += 1 }
            var after = le
            if after < n { after += (bytes[after] == carriageReturn && after + 1 < n && bytes[after + 1] == newline) ? 2 : 1 }
            var c = ls
            while c < le && (bytes[c] == space || bytes[c] == tab) { c += 1 }
            let indent = c - ls
            let blank = (c == le)
            let comment = (c < le && bytes[c] == hash)
            if !blank && indent < childCol { break }                       // dedent → block ends
            if !blank && !(indent == childCol && comment) { anchorEnd = after }   // a data line
            ls = after
        }
        guard anchorEnd >= 0 else { throw YAMLEditError.unsupportedValueShape(path: path) }

        var line = childIndent
        line.append(contentsOf: keyToken.utf8)
        line.append(colon); line.append(space)
        line.append(contentsOf: valueToken.utf8)

        if anchorEnd > 0 && (bytes[anchorEnd - 1] == newline || bytes[anchorEnd - 1] == carriageReturn) {
            // Anchor line ends with a terminator; the new line follows with its own.
            if anchorEnd >= 2 && bytes[anchorEnd - 1] == newline && bytes[anchorEnd - 2] == carriageReturn {
                line.append(carriageReturn); line.append(newline)
            } else if bytes[anchorEnd - 1] == carriageReturn {
                line.append(carriageReturn)
            } else {
                line.append(newline)
            }
            return String(decoding: bytes[0..<anchorEnd] + line + bytes[anchorEnd...], as: UTF8.self)
        } else {
            // Last line had no terminator (end of file): separate with a line break
            // matching the document's style — CRLF if it uses CRLF, else LF.
            var sep: [UInt8] = [newline]
            var k = anchorEnd - 1
            while k >= 0 && bytes[k] != newline { k -= 1 }
            if k >= 1 && bytes[k - 1] == carriageReturn { sep = [carriageReturn, newline] }
            return String(decoding: bytes[0..<anchorEnd] + sep + line + bytes[anchorEnd...], as: UTF8.self)
        }
    }

    /// The index of the `:` separating key from value on a block-mapping line
    /// `[lineStart, lineEnd)` — quote-aware, so a `:` inside a quoted key is skipped.
    /// The separator is a `:` at end-of-line or followed by a space/tab.
    private static func keyValueColon(_ bytes: [UInt8], _ lineStart: Int, _ lineEnd: Int) -> Int? {
        var i = lineStart
        while i < lineEnd && (bytes[i] == space || bytes[i] == tab) { i += 1 }   // indent
        if i < lineEnd && (bytes[i] == quoteDouble || bytes[i] == quoteSingle) {
            let q = bytes[i]; i += 1
            while i < lineEnd {
                if q == quoteDouble && bytes[i] == backslash { i += 2; continue }
                if bytes[i] == q {
                    if q == quoteSingle && i + 1 < lineEnd && bytes[i + 1] == quoteSingle { i += 2; continue }
                    i += 1; break
                }
                i += 1
            }
        }
        while i < lineEnd {
            if bytes[i] == colon && (i + 1 == lineEnd || bytes[i + 1] == space || bytes[i + 1] == tab) { return i }
            i += 1
        }
        return nil
    }
}

/// A path into a YAML document: an array of string keys and integer indices,
/// modeled on Foundation's `[CodingKey]` / `codingPath`. Written directly with
/// literals: `["server", "port"]`, `["servers", 0, "port"]`.
public enum YAMLPath {
    public enum Component: Equatable, Sendable,
        ExpressibleByStringLiteral, ExpressibleByIntegerLiteral
    {
        case key(String)
        case index(Int)
        public init(stringLiteral value: String) { self = .key(value) }
        public init(integerLiteral value: Int) { self = .index(value) }
    }
}

/// Errors from ``YAMLEditor/set(_:at:to:)``, ``YAMLEditor/unset(_:at:)``, and
/// ``YAMLEditor/insert(_:at:to:)``.
/// Path-bearing cases carry the trail from the document root to the failure, like
/// `DecodingError.Context.codingPath`.
public enum YAMLEditError: Error, Sendable {
    /// The input was not well-formed YAML; the wrapped error carries the position.
    case malformedDocument(YAMLError)
    /// The document uses anchors/aliases, which this version cannot edit safely.
    case documentUsesAnchorsOrAliases
    /// No value exists at the given path.
    case pathNotFound(path: [YAMLPath.Component])
    /// The target is a map or sequence, not a single value.
    case notASingleValue(path: [YAMLPath.Component])
    /// The target's shape is not editable/removable yet: a quoted-multiline,
    /// block, or multi-line value; an empty (null) value; a byte-offset skew (e.g.
    /// a leading byte-order mark); or — specific to `unset` — a value on a
    /// continuation line, a key sharing a `-` marker's line (compact block
    /// sequence), or a scalar inside an inline `[…]`/`{…}` collection.
    case unsupportedValueShape(path: [YAMLPath.Component])
    /// A real value already exists at the given path. Thrown by ``YAMLEditor/insert(_:at:to:)``,
    /// which only fills a null or adds a missing key — use ``YAMLEditor/set(_:at:to:)`` to
    /// change a value that is already there. An empty string (`""`) counts as a real value.
    case valueAlreadyPresent(path: [YAMLPath.Component])
}
