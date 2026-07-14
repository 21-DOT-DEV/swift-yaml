import yamlcppShims

/// Surgical, comment-preserving edits: change one scalar value in the original
/// YAML text, leaving comments, blank lines, key order, indentation, and quoting
/// everywhere else byte-for-byte identical — the textual diff covers only the
/// edited value. It never re-emits the whole document (which would reformat and
/// drop comments); it locates the value's exact byte span and splices in place.
///
/// See `Specs/002-surgical-value-set/plan.md` for the design and review history.
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
    /// text. Everything outside the edited value stays byte-identical.
    ///
    /// - Throws: ``YAMLEditError`` — a malformed document, an anchor/alias
    ///   document (which cannot be edited safely), a path that does not resolve,
    ///   a target that is a map/sequence, or a value shape this version does not
    ///   edit yet (quoted-multiline, block, flow, or empty).
    public static func set(_ yaml: String, at path: [YAMLPath.Component], to value: Value) throws -> String {
        let bytes = Array(yaml.utf8)

        // 1. Refuse anchor/alias documents. yaml-cpp collapses an alias onto its
        //    anchor, so an alias target would silently splice the anchor value.
        if documentUsesAnchorsOrAliases(bytes) {
            throw YAMLEditError.documentUsesAnchorsOrAliases
        }

        return try yaml.withCString { cstr -> String in
            // 2. Parse, guarded.
            let result = yamlx.parse(cstr)
            guard result.ok else {
                throw YAMLEditError.malformedDocument(
                    .parse(message: String(yamlx.parseMessage(result)),
                           line: Int(result.line) + 1,
                           column: Int(result.column) + 1))
            }

            // 3. Navigate, validating each step — never index an undefined node.
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

            // 4. Classify the target.
            switch kind(node) {
            case kindScalar: break
            case kindSequence, kindMap: throw YAMLEditError.notASingleValue(path: path)
            default: throw YAMLEditError.unsupportedValueShape(path: path)   // null / undefined
            }

            // 5. Find the span. `valueSpan` gives a reliable end for a plain
            //    single-line scalar; a quoted scalar's end we scan for here.
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

            // 6. Serialize the replacement (no trailing newline), then 7. splice.
            let token = YAMLSerialization.emitScalarToken(value.storage)
            let spliced = bytes[0..<pos] + Array(token.utf8) + bytes[end...]
            return String(decoding: spliced, as: UTF8.self)
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

/// Errors from ``YAMLEditor/set(_:at:to:)``. Path-bearing cases carry the trail
/// from the document root to the failure, like `DecodingError.Context.codingPath`.
public enum YAMLEditError: Error, Sendable {
    /// The input was not well-formed YAML; the wrapped error carries the position.
    case malformedDocument(YAMLError)
    /// The document uses anchors/aliases, which this version cannot edit safely.
    case documentUsesAnchorsOrAliases
    /// No value exists at the given path.
    case pathNotFound(path: [YAMLPath.Component])
    /// The target is a map or sequence, not a single value.
    case notASingleValue(path: [YAMLPath.Component])
    /// The target's shape is not editable yet (quoted-multiline, block, flow,
    /// empty, or a byte-offset skew such as a leading byte-order mark).
    case unsupportedValueShape(path: [YAMLPath.Component])
}
