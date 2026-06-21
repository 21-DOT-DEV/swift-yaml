/// Encodes `Encodable` values to YAML text, modeled on Foundation's
/// `JSONEncoder`.
///
/// ```swift
/// import YAML
///
/// struct Server: Codable { var host: String; var port: Int }
/// let yaml = try YAMLEncoder().encode(Server(host: "localhost", port: 8080))
/// // host: localhost
/// // port: 8080
/// ```
///
/// Like `JSONEncoder`, the top-level call returns the serialized document; for
/// a text format that is a `String`. Bytes are a trivial `Array(yaml.utf8)`.
public final class YAMLEncoder {

    /// Formatting toggles for the emitted document — the YAML analogue of
    /// `JSONEncoder.OutputFormatting`.
    public struct OutputFormatting: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        /// Sort mapping keys lexicographically instead of preserving the
        /// `Codable` declaration order.
        public static let sortedKeys = OutputFormatting(rawValue: 1 << 0)

        /// Emit compact inline (`{a: 1, b: 2}` / `[1, 2]`) flow style instead of
        /// the default multi-line block style.
        public static let flowStyle = OutputFormatting(rawValue: 1 << 1)
    }

    /// How `CodingKey`s map onto emitted mapping keys.
    public enum KeyEncodingStrategy: Sendable {
        /// Emit each key exactly as the type's `CodingKeys` spell it.
        case useDefaultKeys

        /// Convert `camelCase` property names to `snake_case` mapping keys.
        ///
        /// Mirrors `JSONEncoder.KeyEncodingStrategy.convertToSnakeCase`,
        /// including acronym boundaries — `myURLValue` is emitted as
        /// `my_url_value`. The inverse on decode is
        /// ``YAMLDecoder/KeyDecodingStrategy/convertFromSnakeCase``.
        case convertToSnakeCase

        /// Derive each mapping key from a closure applied to the coding path.
        ///
        /// The closure receives the full coding path to the value being
        /// encoded — its last element is the key in question — and returns the
        /// key to emit; the returned key's `stringValue` becomes the mapping
        /// key. The closure must be `@Sendable`.
        case custom(@Sendable ([any CodingKey]) -> any CodingKey)
    }

    /// How non-finite floating-point values are emitted. YAML has native
    /// `.inf`/`.nan`, so unlike `JSONEncoder` the default emits them rather than
    /// throwing.
    public enum NonConformingFloatEncodingStrategy: Sendable {
        /// Emit infinity and NaN using YAML's native core-schema tokens —
        /// `.inf`, `-.inf`, and `.nan`. This is the default, and the reason
        /// the encoder does not throw on non-finite floats the way
        /// `JSONEncoder` does (JSON has no syntax for them).
        case nativeYAML

        /// Throw an `EncodingError.invalidValue` when a non-finite `Double` or
        /// `Float` is encountered, matching `JSONEncoder`'s strict default.
        case `throw`

        /// Encode infinity and NaN as the given placeholder strings.
        ///
        /// Use this for interchange with readers that expect sentinel strings
        /// (for example `"+Infinity"`/`"-Infinity"`/`"NaN"`). The same three
        /// strings decode back to the corresponding values via
        /// ``YAMLDecoder/NonConformingFloatDecodingStrategy/convertFromString(positiveInfinity:negativeInfinity:nan:)``.
        ///
        /// - Parameters:
        ///   - positiveInfinity: The text emitted for `+.infinity`.
        ///   - negativeInfinity: The text emitted for `-.infinity`.
        ///   - nan: The text emitted for `.nan`.
        case convertToString(positiveInfinity: String, negativeInfinity: String, nan: String)
    }

    /// Number of spaces per indentation level (default 2).
    public var indent: Int = 2

    /// Document formatting toggles (default none).
    public var outputFormatting: OutputFormatting = []

    /// Key-name transformation (default `.useDefaultKeys`).
    public var keyEncodingStrategy: KeyEncodingStrategy = .useDefaultKeys

    /// Non-finite float handling (default `.nativeYAML`).
    public var nonConformingFloatEncodingStrategy: NonConformingFloatEncodingStrategy = .nativeYAML

    #if canImport(FoundationEssentials) || canImport(Foundation)
    /// `Date` handling (default `.iso8601`). Available when Foundation is.
    public var dateEncodingStrategy: DateEncodingStrategy = .iso8601

    /// `Data` handling (default `.base64`). Available when Foundation is.
    public var dataEncodingStrategy: DataEncodingStrategy = .base64
    #endif

    /// Contextual information made available to types during encoding.
    public var userInfo: [CodingUserInfoKey: any Sendable] = [:]

    /// Creates an encoder with the default options.
    ///
    /// Every strategy starts at its default (``KeyEncodingStrategy/useDefaultKeys``,
    /// ``NonConformingFloatEncodingStrategy/nativeYAML``, two-space ``indent``,
    /// no ``outputFormatting`` flags); set the properties above to customize.
    public init() {}

    /// Encodes `value` and returns the YAML document as a `String`.
    ///
    /// The value's `Codable` representation is realized in pure Swift and then
    /// serialized in a single pass, so the result is a complete YAML document
    /// (terminated by a trailing newline). To obtain bytes instead, wrap the
    /// result — `Array(yaml.utf8)` or `Data(yaml.utf8)`.
    ///
    /// - Parameter value: The value to encode. Any `Encodable` type works,
    ///   including nested structures, arrays, dictionaries, and enums.
    /// - Returns: The encoded YAML document.
    /// - Throws: `EncodingError` if a value cannot be represented — for
    ///   example a non-finite `Double` under
    ///   ``NonConformingFloatEncodingStrategy/throw`` — or
    ///   ``YAMLError/emit(_:)`` if the underlying emitter fails to produce
    ///   output.
    public func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = _YAMLEncoder(options: makeOptions())
        let topLevel = try encoder.boxEncodable(value)
        let emitOptions = YAMLSerialization.EmitOptions(
            indent: indent,
            flow: outputFormatting.contains(.flowStyle),
            sortKeys: outputFormatting.contains(.sortedKeys))
        return try YAMLSerialization.emit(topLevel, options: emitOptions)
    }

    private func makeOptions() -> YAMLEncoderOptions {
        #if canImport(FoundationEssentials) || canImport(Foundation)
        return YAMLEncoderOptions(
            keyStrategy: keyEncodingStrategy,
            nonConformingFloat: nonConformingFloatEncodingStrategy,
            userInfo: userInfo,
            dateStrategy: dateEncodingStrategy,
            dataStrategy: dataEncodingStrategy)
        #else
        return YAMLEncoderOptions(
            keyStrategy: keyEncodingStrategy,
            nonConformingFloat: nonConformingFloatEncodingStrategy,
            userInfo: userInfo)
        #endif
    }
}

/// Resolved encoder configuration threaded into the internal encoder and every
/// child container (so a strategy set on the top-level encoder takes effect at
/// every depth).
struct YAMLEncoderOptions {
    let keyStrategy: YAMLEncoder.KeyEncodingStrategy
    let nonConformingFloat: YAMLEncoder.NonConformingFloatEncodingStrategy
    let userInfo: [CodingUserInfoKey: any Sendable]
    #if canImport(FoundationEssentials) || canImport(Foundation)
    let dateStrategy: YAMLEncoder.DateEncodingStrategy
    let dataStrategy: YAMLEncoder.DataEncodingStrategy
    #endif
}
