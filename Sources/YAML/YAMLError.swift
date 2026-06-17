/// Errors specific to YAML that do not map onto the standard-library
/// `DecodingError` / `EncodingError` cases.
///
/// The codec throws `DecodingError` / `EncodingError` (both standard library,
/// not Foundation) for the usual codec failures, matching `JSONDecoder` /
/// `JSONEncoder`. A `YAMLError` is additionally attached as the
/// `underlyingError` of a `DecodingError.dataCorrupted` when a parse or
/// resource-limit failure occurs, so callers can recover structured detail
/// (line/column, which limit was hit) while still catching the familiar type.
public enum YAMLError: Error, CustomStringConvertible, Sendable {
    /// The input was not well-formed YAML. `line`/`column` are 1-based as
    /// reported by yaml-cpp (or 0 when the position is unknown).
    case parse(message: String, line: Int, column: Int)

    /// A safety budget was exceeded (the alias-expansion bomb / deep-nesting /
    /// oversized-input defenses). The associated value describes which.
    case documentTooComplex(String)

    /// The emitter failed to produce output for the encoded value.
    case emit(String)

    public var description: String {
        switch self {
        case let .parse(message, line, column):
            return "YAML parse error at line \(line), column \(column): \(message)"
        case let .documentTooComplex(detail):
            return "YAML document too complex: \(detail)"
        case let .emit(detail):
            return "YAML emit error: \(detail)"
        }
    }
}
