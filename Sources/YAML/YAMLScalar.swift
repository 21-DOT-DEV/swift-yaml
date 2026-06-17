// Scalar interpretation, all in pure Swift (no Foundation): YAML scalars are
// untyped text, so the *decoder* resolves a raw scalar to a requested Swift
// type here, and the *encoder* decides here whether a string must be quoted to
// survive a round-trip as a string. This is the type-resolution layer that
// `JSONDecoder` gets for free from JSON's syntax but YAML must do by schema.
enum YAMLScalar {

    // MARK: Decode-side resolution (raw text → typed)

    /// YAML 1.2 core-schema null tokens (plus empty). yaml-cpp already resolves
    /// these to a Null node, but a quoted `"null"` stays a scalar — so this is
    /// only a backstop for scalars that reach a single-value container.
    static func isNull(_ s: String) -> Bool {
        switch s {
        case "", "~", "null", "Null", "NULL": return true
        default: return false
        }
    }

    /// Lenient boolean resolution covering the YAML 1.1 token set that common
    /// readers (PyYAML, libyaml) accept, so decoding into a `Bool` is forgiving.
    static func bool(_ s: String) -> Bool? {
        switch s {
        case "true", "True", "TRUE", "yes", "Yes", "YES", "on", "On", "ON", "y", "Y":
            return true
        case "false", "False", "FALSE", "no", "No", "NO", "off", "Off", "OFF", "n", "N":
            return false
        default:
            return nil
        }
    }

    /// Parses an integer scalar into a specific width/signedness, honoring YAML
    /// sign, `0x`/`0o`/`0b` radix prefixes, and `_` digit separators.
    static func integer<T: FixedWidthInteger>(_ raw: String, as type: T.Type) -> T? {
        var s = Substring(raw)
        guard !s.isEmpty else { return nil }

        var sign = ""
        if s.first == "+" {
            s = s.dropFirst()
        } else if s.first == "-" {
            sign = "-"
            s = s.dropFirst()
        }
        guard !s.isEmpty else { return nil }

        var radix = 10
        if s.hasPrefix("0x") || s.hasPrefix("0X") {
            radix = 16
            s = s.dropFirst(2)
        } else if s.hasPrefix("0o") || s.hasPrefix("0O") {
            radix = 8
            s = s.dropFirst(2)
        } else if s.hasPrefix("0b") || s.hasPrefix("0B") {
            radix = 2
            s = s.dropFirst(2)
        }

        let digits = s.contains("_") ? String(s.filter { $0 != "_" }) : String(s)
        guard !digits.isEmpty else { return nil }
        return T(sign + digits, radix: radix)
    }

    /// Parses a floating-point scalar, recognizing YAML's native `.inf`/`.nan`
    /// tokens and any caller-supplied strings (for `.convertFromString`).
    static func double(
        _ raw: String,
        positiveInfinity: String? = nil,
        negativeInfinity: String? = nil,
        nan: String? = nil
    ) -> Double? {
        if let positiveInfinity, raw == positiveInfinity { return .infinity }
        if let negativeInfinity, raw == negativeInfinity { return -.infinity }
        if let nan, raw == nan { return .nan }

        switch raw {
        case ".inf", ".Inf", ".INF", "+.inf", "+.Inf", "+.INF": return .infinity
        case "-.inf", "-.Inf", "-.INF": return -.infinity
        case ".nan", ".NaN", ".NAN": return .nan
        default: break
        }

        let cleaned = raw.contains("_") ? String(raw.filter { $0 != "_" }) : raw
        return Double(cleaned)
    }

    // MARK: Encode-side quoting

    /// True when emitting `s` as a plain scalar would let a YAML reader
    /// reinterpret it as a non-string (null/bool/number) or lose surrounding
    /// whitespace — in which case the serializer double-quotes it. Syntactic
    /// quoting (special characters) is left to yaml-cpp's own emitter.
    static func needsQuoting(_ s: String) -> Bool {
        if s.isEmpty { return true }
        if isNull(s) { return true }
        if bool(s) != nil { return true }
        if looksNumeric(s) { return true }
        if let first = s.first, first == " " || first == "\t" { return true }
        if let last = s.last, last == " " || last == "\t" { return true }
        return false
    }

    private static func looksNumeric(_ s: String) -> Bool {
        switch s {
        case ".inf", ".Inf", ".INF", "+.inf", "+.Inf", "+.INF",
             "-.inf", "-.Inf", "-.INF", ".nan", ".NaN", ".NAN":
            return true
        default:
            break
        }
        let cleaned = s.contains("_") ? String(s.filter { $0 != "_" }) : s
        if Double(cleaned) != nil { return true }
        if integer(s, as: Int64.self) != nil { return true }
        if integer(s, as: UInt64.self) != nil { return true }
        return false
    }

    // MARK: Encode-side formatting

    /// Shortest round-trippable text for a finite double (Swift's default
    /// description already guarantees shortest-round-trip); `.inf`/`.nan` use
    /// YAML's native tokens.
    static func format(_ value: Double) -> String {
        if value.isNaN { return ".nan" }
        if value.isInfinite { return value > 0 ? ".inf" : "-.inf" }
        return "\(value)"
    }

    static func format(_ value: Float) -> String {
        if value.isNaN { return ".nan" }
        if value.isInfinite { return value > 0 ? ".inf" : "-.inf" }
        return "\(value)"
    }
}
