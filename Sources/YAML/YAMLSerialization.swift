import yamlcppShims

extension String {
    /// Creates a `String` from a C++-owned byte view (`yamlx.CStr`: a `const char*`
    /// plus a byte length). This mirrors the CxxStdlib overlay's own
    /// `String(_ cxxString: std.string)` initializer, but reads plain C pointer types
    /// so it stays independent of that overlay — which drops out of overload
    /// resolution under whole-module compilation on macOS (see the `CStr` note in
    /// yamlcpp_shims.h and Projects/README.md). NUL-safe (honors the byte length) and,
    /// like `String(_: std.string)`, repairs ill-formed UTF-8 with U+FFFD.
    init(_ view: yamlx.CStr) {
        guard let base = view.data, view.len > 0 else { self = ""; return }
        self = String(decoding: UnsafeRawBufferPointer(start: UnsafeRawPointer(base), count: view.len), as: UTF8.self)
    }
}

// The two — and only two — boundaries where the overlay crosses into yaml-cpp:
// `parse` (text → YAMLValue, via the guarded `yamlx::parse` + node inspection)
// and `emit` (YAMLValue → text, via the event-streamed `yamlx::` emitter). All
// Codable machinery stays in pure Swift above this file.
enum YAMLSerialization {

    // MARK: Parse (decode boundary)

    struct ParseConfig {
        var maxDepth: Int
        var maxNodeCount: Int
        var maxInputBytes: Int
        var duplicateKeyStrategy: YAMLDecoder.DuplicateKeyStrategy
    }

    static func parse(_ text: String, config: ParseConfig) throws -> YAMLValue {
        if config.maxInputBytes >= 0, text.utf8.count > config.maxInputBytes {
            throw tooComplex("input is \(text.utf8.count) bytes, exceeds limit of \(config.maxInputBytes)")
        }
        // Cheap pre-parse guard: reject pathologically deep nesting before
        // yaml-cpp's parser (and our walk) choke on it. yaml-cpp's flow parser
        // hangs past ~600 deep, and accessing a deeply nested node tree is
        // super-linear (hangs by ~500), so the default budget sits well below.
        if config.maxDepth >= 0 {
            try checkNesting(text, maxDepth: config.maxDepth)
        }

        // Strict duplicate-key rejection (opt-in): an event-driven scan of the
        // first document, run *after* the size/depth guards so untrusted input
        // stays budgeted, and only when `.reject` is chosen. Detected duplicates
        // surface as `DecodingError.dataCorrupted` wrapping a `YAMLError`, like
        // the parse path — a bare `YAMLError` never escapes to the caller.
        if config.duplicateKeyStrategy == .reject {
            let dup = text.withCString { yamlx.firstDuplicateKey($0) }
            if dup.found {
                let yamlError = YAMLError.duplicateKey(
                    key: String(dup.key),
                    line: Int(dup.line) + 1,
                    column: Int(dup.column) + 1)
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: [],
                        debugDescription: yamlError.description,
                        underlyingError: yamlError))
            }
        }

        let result = text.withCString { yamlx.parse($0) }
        guard result.ok else {
            let yamlError = YAMLError.parse(
                message: String(yamlx.parseMessage(result)),
                line: Int(result.line) + 1,
                column: Int(result.column) + 1)
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: yamlError.description,
                    underlyingError: yamlError))
        }

        var nodeCount = 0
        return try build(result.root, depth: 0, count: &nodeCount, config: config)
    }

    private static func build(
        _ node: yamlx.Node,
        depth: Int,
        count: inout Int,
        config: ParseConfig
    ) throws -> YAMLValue {
        if config.maxDepth >= 0, depth > config.maxDepth {
            throw tooComplex("nesting exceeds maximum depth of \(config.maxDepth)")
        }
        count += 1
        if config.maxNodeCount >= 0, count > config.maxNodeCount {
            // The alias-expansion ("billion laughs") backstop: aliases are
            // shared in the parsed graph, so materializing a bomb inflates this
            // counter and trips here long before exhausting memory.
            throw tooComplex("document exceeds maximum of \(config.maxNodeCount) nodes")
        }

        switch yamlx.nodeKind(node) {
        case 1:  // null
            return .null
        case 2:  // scalar
            return .string(String(yamlx.scalarText(node)))
        case 3:  // sequence
            let n = Int(yamlx.count(node))
            var items = [YAMLValue]()
            items.reserveCapacity(n)
            for i in 0..<n {
                items.append(try build(yamlx.seqItem(node, i), depth: depth + 1, count: &count, config: config))
            }
            return .sequence(items)
        case 4:  // map
            let n = Int(yamlx.count(node))
            var mapping = YAMLMapping()
            for i in 0..<n {
                let key = String(yamlx.mapKeyText(node, i))
                // yaml-cpp exposes both entries of a repeated key here (its map
                // iteration is not deduplicated), so apply the strategy *before*
                // building the value. The contains-check drives `.useFirst`
                // (first occurrence wins, later values skipped) and `.useLast`
                // (fall through to overwrite) uniformly, including the degenerate
                // "" bucket that non-scalar keys collapse into (they carry no text,
                // so `mapKeyText` yields "").
                if mapping.contains(key) {
                    switch config.duplicateKeyStrategy {
                    case .reject:
                        // Only a **non-empty** key is rejected here. An empty key
                        // text is ambiguous — a genuine "" scalar key, or a
                        // non-scalar key (null, alias, sequence, mapping) that has
                        // no text and collapses into the "" bucket. Two "" *scalar*
                        // keys are already rejected by the byte pre-pass (which
                        // never inserts non-scalar keys), so gating on non-empty
                        // avoids a false duplicate when a non-scalar key and a
                        // distinct "" scalar key collide, and matches the
                        // documented scope (non-scalar keys aren't compared). The
                        // net still catches a non-empty repeat the pre-pass missed
                        // — e.g. NFC vs NFD keys, canonically equal but
                        // byte-distinct — reporting the key's own mark.
                        if !key.isEmpty {
                            let m = yamlx.mark(yamlx.mapKey(node, i))
                            let err = YAMLError.duplicateKey(
                                key: key,
                                line: m.ok ? Int(m.line) + 1 : 0,
                                column: m.ok ? Int(m.column) + 1 : 0)
                            throw DecodingError.dataCorrupted(
                                DecodingError.Context(
                                    codingPath: [], debugDescription: err.description, underlyingError: err))
                        }
                    case .useFirst:
                        continue                 // keep the first occurrence; skip its value
                    case .useLast:
                        break                    // fall through to build + overwrite
                    }
                }
                let value = try build(yamlx.mapValue(node, i), depth: depth + 1, count: &count, config: config)
                mapping.set(value, forKey: key)
            }
            return .mapping(mapping)
        default:  // undefined
            return .null
        }
    }

    private static func tooComplex(_ detail: String) -> DecodingError {
        let yamlError = YAMLError.documentTooComplex(detail)
        return DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: [],
                debugDescription: yamlError.description,
                underlyingError: yamlError))
    }

    /// Conservative single-pass upper bound on nesting depth, covering every
    /// cheap depth bomb: flow brackets (`[[[…`), compact block sequences/maps
    /// (`- - - -…` / `? ? ?…`), and indentation (each leading space is at most
    /// one block level). Quote-aware so brackets inside scalars aren't counted.
    /// Over-counting is safe (it only rejects sooner); the only false positive
    /// is a line with more than `maxDepth` leading spaces, which is absurd for
    /// the generous default.
    private static func checkNesting(_ text: String, maxDepth: Int) throws {
        var flowDepth = 0          // running [ { depth, carried across lines
        var quote: UInt8? = nil
        var escaped = false
        var atLineStart = true     // still in the leading indent/indicator region
        var lineIndent = 0         // leading spaces on the current line
        var compactRun = 0         // consecutive "- " / "? " block indicators

        let bytes = Array(text.utf8)
        let n = bytes.count
        var i = 0
        while i < n {
            let byte = bytes[i]

            if let q = quote {
                if q == 0x22 {  // double quote: honor backslash escapes
                    if escaped { escaped = false }
                    else if byte == 0x5C { escaped = true }
                    else if byte == 0x22 { quote = nil }
                } else if byte == 0x27 {  // single quote
                    quote = nil
                }
                i += 1
                continue
            }

            if byte == 0x0A {  // newline → reset per-line block state
                atLineStart = true
                lineIndent = 0
                compactRun = 0
                i += 1
                continue
            }

            // Leading region: indentation and compact block indicators only
            // count as block nesting outside of flow context.
            if atLineStart && flowDepth == 0 {
                if byte == 0x20 {  // space
                    lineIndent += 1
                    if lineIndent > maxDepth {
                        throw tooComplex("indentation depth exceeds maximum of \(maxDepth)")
                    }
                    i += 1
                    continue
                }
                if (byte == 0x2D || byte == 0x3F), i + 1 < n, bytes[i + 1] == 0x20 {  // "- " or "? "
                    compactRun += 1
                    if lineIndent + compactRun > maxDepth {
                        throw tooComplex("block nesting exceeds maximum depth of \(maxDepth)")
                    }
                    i += 2
                    continue
                }
                atLineStart = false  // leading region ended; handle this byte below
            }

            switch byte {
            case 0x22: quote = 0x22       // "
            case 0x27: quote = 0x27       // '
            case 0x5B, 0x7B:              // [ {
                flowDepth += 1
                if flowDepth > maxDepth {
                    throw tooComplex("flow nesting exceeds maximum depth of \(maxDepth)")
                }
            case 0x5D, 0x7D:              // ] }
                if flowDepth > 0 { flowDepth -= 1 }
            default:
                break
            }
            i += 1
        }
    }

    // MARK: Emit (encode boundary)

    struct EmitOptions {
        var indent: Int
        var flow: Bool
        var sortKeys: Bool
    }

    static func emit(_ value: YAMLValue, options: EmitOptions) throws -> String {
        let emitter = yamlx.newEmitter()
        defer { yamlx.freeEmitter(emitter) }
        yamlx.emitterSetIndent(emitter, options.indent)

        write(value, to: emitter, options: options)

        guard yamlx.emitterOK(emitter) else {
            throw YAMLError.emit(String(yamlx.emitterError(emitter)))
        }
        var text = String(yamlx.emitterText(emitter))
        if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        return text
    }

    /// Emits a single scalar as an inline token — no trailing newline — reusing
    /// the exact per-kind formatting and quoting `write` uses for whole-document
    /// output. `YAMLEditor` splices the result in place, so producing the same
    /// bytes the emitter would means the edit re-parses to the intended value.
    static func emitScalarToken(_ value: YAMLValue) -> String {
        let emitter = yamlx.newEmitter()
        defer { yamlx.freeEmitter(emitter) }
        write(value, to: emitter, options: EmitOptions(indent: 2, flow: false, sortKeys: false))
        return String(yamlx.emitterText(emitter))
    }

    private static func write(
        _ value: YAMLValue,
        to emitter: UnsafeMutableRawPointer?,
        options: EmitOptions
    ) {
        switch value {
        case .null:
            yamlx.emitNull(emitter)
        case .bool(let b):
            emitScalar(b ? "true" : "false", quoted: false, to: emitter)
        case .int(let i):
            emitScalar(String(i), quoted: false, to: emitter)
        case .uint(let u):
            emitScalar(String(u), quoted: false, to: emitter)
        case .double(let d):
            emitScalar(YAMLScalar.format(d), quoted: false, to: emitter)
        case .float(let f):
            emitScalar(YAMLScalar.format(f), quoted: false, to: emitter)
        case .string(let s):
            emitScalar(s, quoted: YAMLScalar.needsQuoting(s), to: emitter)
        case .sequence(let items):
            yamlx.beginSeq(emitter, options.flow)
            for item in items { write(item, to: emitter, options: options) }
            yamlx.endSeq(emitter)
        case .mapping(let mapping):
            yamlx.beginMap(emitter, options.flow)
            let pairs = options.sortKeys ? mapping.sortedPairs() : mapping.pairs
            for pair in pairs {
                yamlx.emitKeyToken(emitter)
                emitScalar(pair.key, quoted: YAMLScalar.needsQuoting(pair.key), to: emitter)
                yamlx.emitValueToken(emitter)
                write(pair.value, to: emitter, options: options)
            }
            yamlx.endMap(emitter)
        }
    }

    private static func emitScalar(_ text: String, quoted: Bool, to emitter: UnsafeMutableRawPointer?) {
        text.withCString { cstr in
            if quoted {
                yamlx.emitQuotedScalar(emitter, cstr)
            } else {
                yamlx.emitPlainScalar(emitter, cstr)
            }
        }
    }
}
