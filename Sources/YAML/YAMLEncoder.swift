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
        case useDefaultKeys
        case convertToSnakeCase
        case custom(@Sendable ([any CodingKey]) -> any CodingKey)
    }

    /// How non-finite floating-point values are emitted. YAML has native
    /// `.inf`/`.nan`, so unlike `JSONEncoder` the default emits them rather than
    /// throwing.
    public enum NonConformingFloatEncodingStrategy: Sendable {
        case nativeYAML
        case `throw`
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

    public init() {}

    /// Encodes `value` and returns the YAML document as a `String`.
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
