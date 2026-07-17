/// Errors specific to YAML that do not map onto the standard-library
/// `DecodingError` / `EncodingError` cases.
///
/// The codec throws `DecodingError` / `EncodingError` (both standard library,
/// not Foundation) for the usual codec failures, matching `JSONDecoder` /
/// `JSONEncoder`. A `YAMLError` is additionally attached as the
/// `underlyingError` of a `DecodingError.dataCorrupted` when a parse or
/// resource-limit failure occurs, so callers can recover structured detail
/// (line/column, which limit was hit) while still catching the familiar type.
///
/// - Note: This enum is **not frozen** — future versions may add cases (for
///   example, streaming or further resource-limit errors). Code that switches
///   exhaustively over a `YAMLError` should include an `@unknown default:` case
///   so a new case stays source-compatible on recompile (see Swift Evolution
///   SE-0192). Most callers catch `DecodingError` and never switch the wrapped
///   error, so they are unaffected.
public enum YAMLError: Error, CustomStringConvertible, Sendable {
    /// The input was not well-formed YAML. `line`/`column` are 1-based — the
    /// overlay adds 1 to yaml-cpp's 0-based marks (or 0 when the position is
    /// unknown).
    case parse(message: String, line: Int, column: Int)

    /// A safety budget was exceeded (the alias-expansion bomb / deep-nesting /
    /// oversized-input defenses). The associated value describes which.
    case documentTooComplex(String)

    /// The emitter failed to produce output for the encoded value.
    case emit(String)

    /// A mapping key appeared twice, rejected under
    /// ``YAMLDecoder/DuplicateKeyStrategy/reject``. `line`/`column` are 1-based
    /// (the overlay adds 1 to yaml-cpp's 0-based marks).
    case duplicateKey(key: String, line: Int, column: Int)

    public var description: String {
        switch self {
        case let .parse(message, line, column):
            return "YAML parse error at line \(line), column \(column): \(message)"
        case let .documentTooComplex(detail):
            return "YAML document too complex: \(detail)"
        case let .emit(detail):
            return "YAML emit error: \(detail)"
        case let .duplicateKey(key, line, column):
            return "duplicate mapping key '\(key)' at line \(line), column \(column)"
        }
    }
}
