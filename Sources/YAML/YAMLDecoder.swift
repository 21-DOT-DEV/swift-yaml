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
        /// Match each `CodingKey` against the mapping key verbatim.
        case useDefaultKeys

        /// Convert `snake_case` mapping keys to `camelCase` before matching
        /// against `CodingKeys`.
        ///
        /// Mirrors `JSONDecoder.KeyDecodingStrategy.convertFromSnakeCase` and
        /// is the inverse of
        /// ``YAMLEncoder/KeyEncodingStrategy/convertToSnakeCase``:
        /// `my_url_value` resolves to `myURLValue`, preserving any leading or
        /// trailing underscores.
        case convertFromSnakeCase

        /// Derive each lookup key from a closure applied to the coding path.
        ///
        /// The closure receives the full coding path — its last element is the
        /// key being decoded — and returns the key to look up in the mapping.
        /// The closure must be `@Sendable`.
        case custom(@Sendable ([any CodingKey]) -> any CodingKey)
    }

    /// How non-finite floating-point values are recognized.
    public enum NonConformingFloatDecodingStrategy: Sendable {
        /// Recognize YAML's native `.inf`, `-.inf`, and `.nan` tokens (in any
        /// capitalization the core schema allows) as the corresponding
        /// floating-point values. This is the default.
        case nativeYAML

        /// Throw a `DecodingError` rather than resolving any infinity or NaN
        /// representation, matching `JSONDecoder`'s strict default.
        case `throw`

        /// Recognize the given placeholder strings as infinity and NaN.
        ///
        /// The inverse of
        /// ``YAMLEncoder/NonConformingFloatEncodingStrategy/convertToString(positiveInfinity:negativeInfinity:nan:)``;
        /// supply the same three strings the encoder used.
        ///
        /// - Parameters:
        ///   - positiveInfinity: The text decoded as `+.infinity`.
        ///   - negativeInfinity: The text decoded as `-.infinity`.
        ///   - nan: The text decoded as `.nan`.
        case convertFromString(positiveInfinity: String, negativeInfinity: String, nan: String)
    }

    /// How duplicate mapping keys are resolved. Note: yaml-cpp's parser
    /// collapses duplicate keys (last value wins) before the overlay observes
    /// the document, so on this engine both options behave as last-wins for
    /// genuinely repeated keys; strict rejection is a documented future tier.
    public enum DuplicateKeyStrategy: Sendable, Equatable {
        /// Keep the value of the first occurrence of a repeated key.
        ///
        /// Note: on this engine yaml-cpp collapses duplicates before the
        /// overlay observes the document, so a genuinely repeated key already
        /// resolves to its last value — see the type-level discussion.
        case useFirst

        /// Keep the value of the last occurrence of a repeated key. This is
        /// the default and matches yaml-cpp's own behavior.
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

        /// Creates a set of document limits.
        ///
        /// The defaults are generous enough that ordinary configuration and
        /// data-interchange documents never reach them; pass a negative value
        /// for any parameter to disable that individual limit, or use
        /// ``unbounded`` to disable all three.
        ///
        /// - Parameters:
        ///   - maxDepth: Maximum nesting depth of collections within
        ///     collections. Default `128`.
        ///   - maxNodeCount: Maximum number of nodes materialized while
        ///     building the value tree — the alias-bomb backstop. Default
        ///     `10_000_000`.
        ///   - maxInputBytes: Maximum input size in UTF-8 bytes. Default
        ///     `52_428_800` (50 MiB).
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

    /// Creates a decoder with the default options.
    ///
    /// Every strategy starts at its default and ``documentLimits`` starts at
    /// ``DocumentLimits/default``, so a freshly created decoder is already
    /// safe to point at untrusted input; set the properties above to customize.
    public init() {}

    /// Decodes a value of `type` from a YAML `String`.
    ///
    /// The text is parsed once — under the active ``documentLimits`` — into an
    /// intermediate tree, which the `Codable` machinery then walks to produce
    /// `T`. YAML scalars are untyped, so each scalar is resolved to the
    /// concrete Swift type the container asks for.
    ///
    /// If the text holds several `---`-separated documents, only the **first**
    /// is decoded; any following documents are ignored (no error is raised).
    /// Decoding every document in a stream is a separate, future entry point.
    ///
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - yaml: The YAML text to read (first document only, if it is a stream).
    /// - Returns: The decoded value.
    /// - Throws: `DecodingError` for the usual `Codable` failures (type
    ///   mismatch, missing key, and so on); `DecodingError.dataCorrupted`
    ///   wrapping a ``YAMLError`` when the input is malformed
    ///   (``YAMLError/parse(message:line:column:)``) or exceeds a safety
    ///   budget (``YAMLError/documentTooComplex(_:)``).
    public func decode<T: Decodable>(_ type: T.Type, from yaml: String) throws -> T {
        let value = try YAMLSerialization.parse(yaml, config: parseConfig)
        let decoder = _YAMLDecoder(value: value, options: makeOptions(), codingPath: [])
        return try decoder.unbox(value, as: type, at: [])
    }

    /// Decodes a value of `type` from UTF-8 encoded YAML bytes.
    ///
    /// The Foundation-free entry point: it decodes the bytes as UTF-8 and
    /// forwards to the `String` overload of `decode(_:from:)`, so the same
    /// strategies, limits, and errors apply — including decoding only the first
    /// document of a multi-document stream. Use it on platforms without
    /// Foundation, or any time the document is already in a `[UInt8]` buffer.
    ///
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - data: The UTF-8 encoded YAML text to read (first document only, if it is a stream).
    /// - Returns: The decoded value.
    /// - Throws: The same errors as the `String` overload — `DecodingError`,
    ///   including `dataCorrupted` wrapping a ``YAMLError`` for malformed or
    ///   over-budget input.
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
