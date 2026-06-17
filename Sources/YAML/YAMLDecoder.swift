/// Decodes `Decodable` values from YAML text, modeled on Foundation's
/// `JSONDecoder`.
///
/// ```swift
/// import YAML
///
/// struct Server: Codable { var host: String; var port: Int }
/// let server = try YAMLDecoder().decode(Server.self, from: "host: localhost\nport: 8080")
/// ```
///
/// The decoder is **safe by default**: input is bounded by `documentLimits`,
/// which reject alias-expansion ("billion laughs") bombs, pathologically deep
/// nesting, and oversized payloads before they exhaust memory or the parser
/// stack. Set `documentLimits = .unbounded` only for fully trusted input.
public final class YAMLDecoder {

    /// How mapping keys map onto `CodingKey`s.
    public enum KeyDecodingStrategy: Sendable {
        case useDefaultKeys
        case convertFromSnakeCase
        case custom(@Sendable ([any CodingKey]) -> any CodingKey)
    }

    /// How non-finite floating-point values are recognized.
    public enum NonConformingFloatDecodingStrategy: Sendable {
        case nativeYAML
        case `throw`
        case convertFromString(positiveInfinity: String, negativeInfinity: String, nan: String)
    }

    /// How duplicate mapping keys are resolved. Note: yaml-cpp's parser
    /// collapses duplicate keys (last value wins) before the overlay observes
    /// the document, so on this engine both options behave as last-wins for
    /// genuinely repeated keys; strict rejection is a documented future tier.
    public enum DuplicateKeyStrategy: Sendable, Equatable {
        case useFirst
        case useLast
    }

    /// Resource budgets applied while parsing untrusted input. A negative value
    /// disables that individual limit.
    public struct DocumentLimits: Sendable {
        /// Maximum nesting depth (collections within collections). Kept well
        /// below `JSONDecoder`'s 512 because yaml-cpp's recursive parser hangs
        /// past ~600 deep and accessing a deeply nested node tree is
        /// super-linear (hangs by ~500); 128 is far beyond any real document.
        public var maxDepth: Int
        /// Maximum total number of nodes materialized — the alias-bomb backstop.
        public var maxNodeCount: Int
        /// Maximum input size in UTF-8 bytes.
        public var maxInputBytes: Int

        public init(maxDepth: Int = 128, maxNodeCount: Int = 10_000_000, maxInputBytes: Int = 50 * 1024 * 1024) {
            self.maxDepth = maxDepth
            self.maxNodeCount = maxNodeCount
            self.maxInputBytes = maxInputBytes
        }

        /// Generous defaults that ordinary documents never reach.
        public static let `default` = DocumentLimits()

        /// All limits disabled — for fully trusted input only.
        public static let unbounded = DocumentLimits(maxDepth: -1, maxNodeCount: -1, maxInputBytes: -1)
    }

    /// Key-name transformation (default `.useDefaultKeys`).
    public var keyDecodingStrategy: KeyDecodingStrategy = .useDefaultKeys

    /// Non-finite float handling (default `.nativeYAML`).
    public var nonConformingFloatDecodingStrategy: NonConformingFloatDecodingStrategy = .nativeYAML

    /// Duplicate-key resolution (default `.useLast`).
    public var duplicateKeyStrategy: DuplicateKeyStrategy = .useLast

    /// Resource budgets for untrusted input (default `.default`).
    public var documentLimits: DocumentLimits = .default

    #if canImport(FoundationEssentials) || canImport(Foundation)
    /// `Date` handling (default `.iso8601`). Available when Foundation is.
    public var dateDecodingStrategy: DateDecodingStrategy = .iso8601

    /// `Data` handling (default `.base64`). Available when Foundation is.
    public var dataDecodingStrategy: DataDecodingStrategy = .base64
    #endif

    /// Contextual information made available to types during decoding.
    public var userInfo: [CodingUserInfoKey: any Sendable] = [:]

    public init() {}

    /// Decodes a value of `type` from a YAML `String`.
    public func decode<T: Decodable>(_ type: T.Type, from yaml: String) throws -> T {
        let value = try YAMLSerialization.parse(yaml, config: parseConfig)
        let decoder = _YAMLDecoder(value: value, options: makeOptions(), codingPath: [])
        return try decoder.unbox(value, as: type, at: [])
    }

    /// Decodes a value of `type` from UTF-8 encoded YAML bytes (Foundation-free).
    public func decode<T: Decodable>(_ type: T.Type, from data: [UInt8]) throws -> T {
        try decode(type, from: String(decoding: data, as: UTF8.self))
    }

    private var parseConfig: YAMLSerialization.ParseConfig {
        YAMLSerialization.ParseConfig(
            maxDepth: documentLimits.maxDepth,
            maxNodeCount: documentLimits.maxNodeCount,
            maxInputBytes: documentLimits.maxInputBytes,
            duplicateKeyStrategy: duplicateKeyStrategy)
    }

    private func makeOptions() -> YAMLDecoderOptions {
        #if canImport(FoundationEssentials) || canImport(Foundation)
        return YAMLDecoderOptions(
            keyStrategy: keyDecodingStrategy,
            nonConformingFloat: nonConformingFloatDecodingStrategy,
            userInfo: userInfo,
            dateStrategy: dateDecodingStrategy,
            dataStrategy: dataDecodingStrategy)
        #else
        return YAMLDecoderOptions(
            keyStrategy: keyDecodingStrategy,
            nonConformingFloat: nonConformingFloatDecodingStrategy,
            userInfo: userInfo)
        #endif
    }
}

/// Resolved decoder configuration threaded into the internal decoder and every
/// child container.
struct YAMLDecoderOptions {
    let keyStrategy: YAMLDecoder.KeyDecodingStrategy
    let nonConformingFloat: YAMLDecoder.NonConformingFloatDecodingStrategy
    let userInfo: [CodingUserInfoKey: any Sendable]
    #if canImport(FoundationEssentials) || canImport(Foundation)
    let dateStrategy: YAMLDecoder.DateDecodingStrategy
    let dataStrategy: YAMLDecoder.DataDecodingStrategy
    #endif
}
