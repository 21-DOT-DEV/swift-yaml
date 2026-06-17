// The internal decoder and its three containers. The decoder reads the
// `YAMLValue` tree produced by `YAMLSerialization.parse`; scalars are resolved
// to the requested Swift type on demand (the faithful YAML model). Unlike the
// encoder, the decoder needs no referencing subclass — `superDecoder()` returns
// a sibling decoder over the relevant sub-value — so it can be `final`.

final class _YAMLDecoder: Decoder, SingleValueDecodingContainer {
    let value: YAMLValue
    var codingPath: [any CodingKey]
    let options: YAMLDecoderOptions

    var userInfo: [CodingUserInfoKey: Any] { options.userInfo.mapValues { $0 as Any } }

    init(value: YAMLValue, options: YAMLDecoderOptions, codingPath: [any CodingKey]) {
        self.value = value
        self.options = options
        self.codingPath = codingPath
    }

    // MARK: Decoder

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard case .mapping(let mapping) = value else {
            throw typeMismatch([String: Any].self, value, at: codingPath)
        }
        return KeyedDecodingContainer(
            YAMLKeyedDecodingContainer<Key>(decoder: self, mapping: mapping, codingPath: codingPath))
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        guard case .sequence(let elements) = value else {
            throw typeMismatch([Any].self, value, at: codingPath)
        }
        return YAMLUnkeyedDecodingContainer(decoder: self, elements: elements, codingPath: codingPath)
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer { self }

    // MARK: SingleValueDecodingContainer

    func decodeNil() -> Bool {
        if case .null = value { return true }
        return false
    }

    func decode(_ type: Bool.Type) throws -> Bool { try unboxBool(value, at: codingPath) }
    func decode(_ type: String.Type) throws -> String { try unboxString(value, at: codingPath) }
    func decode(_ type: Double.Type) throws -> Double { try unboxDouble(value, at: codingPath) }
    func decode(_ type: Float.Type) throws -> Float { try unboxFloat(value, at: codingPath) }
    func decode(_ type: Int.Type) throws -> Int { try unboxInteger(value, as: Int.self, at: codingPath) }
    func decode(_ type: Int8.Type) throws -> Int8 { try unboxInteger(value, as: Int8.self, at: codingPath) }
    func decode(_ type: Int16.Type) throws -> Int16 { try unboxInteger(value, as: Int16.self, at: codingPath) }
    func decode(_ type: Int32.Type) throws -> Int32 { try unboxInteger(value, as: Int32.self, at: codingPath) }
    func decode(_ type: Int64.Type) throws -> Int64 { try unboxInteger(value, as: Int64.self, at: codingPath) }
    func decode(_ type: UInt.Type) throws -> UInt { try unboxInteger(value, as: UInt.self, at: codingPath) }
    func decode(_ type: UInt8.Type) throws -> UInt8 { try unboxInteger(value, as: UInt8.self, at: codingPath) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { try unboxInteger(value, as: UInt16.self, at: codingPath) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { try unboxInteger(value, as: UInt32.self, at: codingPath) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { try unboxInteger(value, as: UInt64.self, at: codingPath) }
    func decode<T: Decodable>(_ type: T.Type) throws -> T { try unbox(value, as: type, at: codingPath) }

    // MARK: Unboxing

    func unboxBool(_ value: YAMLValue, at path: [any CodingKey]) throws -> Bool {
        switch value {
        case .bool(let b): return b
        case .string(let s):
            if let b = YAMLScalar.bool(s) { return b }
            throw typeMismatch(Bool.self, value, at: path)
        case .null: throw valueNotFound(Bool.self, at: path)
        default: throw typeMismatch(Bool.self, value, at: path)
        }
    }

    func unboxString(_ value: YAMLValue, at path: [any CodingKey]) throws -> String {
        switch value {
        case .string(let s): return s
        case .null: throw valueNotFound(String.self, at: path)
        default: throw typeMismatch(String.self, value, at: path)
        }
    }

    func unboxInteger<T: FixedWidthInteger>(_ value: YAMLValue, as type: T.Type, at path: [any CodingKey]) throws -> T {
        switch value {
        case .int(let i):
            guard let r = T(exactly: i) else { throw numberDoesNotFit(value, type, at: path) }
            return r
        case .uint(let u):
            guard let r = T(exactly: u) else { throw numberDoesNotFit(value, type, at: path) }
            return r
        case .double(let d):
            guard let r = T(exactly: d) else { throw numberDoesNotFit(value, type, at: path) }
            return r
        case .string(let s):
            guard let r = YAMLScalar.integer(s, as: type) else { throw typeMismatch(type, value, at: path) }
            return r
        case .null:
            throw valueNotFound(type, at: path)
        default:
            throw typeMismatch(type, value, at: path)
        }
    }

    func unboxDouble(_ value: YAMLValue, at path: [any CodingKey]) throws -> Double {
        switch value {
        case .double(let d): return try checkFinite(d, Double.self, at: path)
        case .float(let f): return try checkFinite(Double(f), Double.self, at: path)
        case .int(let i): return Double(i)
        case .uint(let u): return Double(u)
        case .string(let s):
            guard let d = parseFloating(s) else { throw typeMismatch(Double.self, value, at: path) }
            return try checkFinite(d, Double.self, at: path)
        case .null: throw valueNotFound(Double.self, at: path)
        default: throw typeMismatch(Double.self, value, at: path)
        }
    }

    func unboxFloat(_ value: YAMLValue, at path: [any CodingKey]) throws -> Float {
        let d = try unboxDouble(value, at: path)
        return Float(d)
    }

    func unbox<T: Decodable>(_ value: YAMLValue, as type: T.Type, at path: [any CodingKey]) throws -> T {
        #if canImport(FoundationEssentials) || canImport(Foundation)
        if let special = try unboxFoundation(value, as: type, at: path) { return special }
        #endif
        let sub = _YAMLDecoder(value: value, options: options, codingPath: path)
        return try T(from: sub)
    }

    /// Floating-point scalar parsing honoring the non-conforming-float strategy.
    private func parseFloating(_ s: String) -> Double? {
        switch options.nonConformingFloat {
        case .nativeYAML:
            return YAMLScalar.double(s)
        case .throw:
            return YAMLScalar.double(s)  // finiteness checked by checkFinite
        case let .convertFromString(positiveInfinity, negativeInfinity, nan):
            return YAMLScalar.double(s, positiveInfinity: positiveInfinity, negativeInfinity: negativeInfinity, nan: nan)
        }
    }

    private func checkFinite<T: BinaryFloatingPoint>(_ value: Double, _ type: T.Type, at path: [any CodingKey]) throws -> Double {
        if value.isFinite { return value }
        if case .throw = options.nonConformingFloat {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: path,
                    debugDescription: "Non-finite \(type) value is not allowed; set nonConformingFloatDecodingStrategy to allow it."))
        }
        return value
    }

    // MARK: Error helpers

    func typeMismatch(_ type: Any.Type, _ value: YAMLValue, at path: [any CodingKey]) -> DecodingError {
        DecodingError.typeMismatch(
            type,
            DecodingError.Context(
                codingPath: path,
                debugDescription: "Expected to decode \(type) but found \(Self.describe(value)) instead."))
    }

    func valueNotFound(_ type: Any.Type, at path: [any CodingKey]) -> DecodingError {
        DecodingError.valueNotFound(
            type,
            DecodingError.Context(
                codingPath: path,
                debugDescription: "Expected \(type) but found null instead."))
    }

    private func numberDoesNotFit(_ value: YAMLValue, _ type: Any.Type, at path: [any CodingKey]) -> DecodingError {
        DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: path,
                debugDescription: "Parsed number \(Self.describe(value)) does not fit in \(type)."))
    }

    static func describe(_ value: YAMLValue) -> String {
        switch value {
        case .null: return "null"
        case .bool: return "a boolean"
        case .int, .uint, .double, .float: return "a number"
        case .string(let s): return "the scalar \"\(s)\""
        case .sequence: return "a sequence"
        case .mapping: return "a mapping"
        }
    }
}

// MARK: - Keyed decoding container

struct YAMLKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    private let decoder: _YAMLDecoder
    private let lookup: [String: YAMLValue]
    private let orderedKeys: [String]
    let codingPath: [any CodingKey]

    init(decoder: _YAMLDecoder, mapping: YAMLMapping, codingPath: [any CodingKey]) {
        self.decoder = decoder
        self.codingPath = codingPath

        var lookup = [String: YAMLValue](minimumCapacity: mapping.count)
        var ordered = [String]()
        for pair in mapping.pairs {
            let decodedKey: String
            switch decoder.options.keyStrategy {
            case .useDefaultKeys:
                decodedKey = pair.key
            case .convertFromSnakeCase:
                decodedKey = KeyStrategyConversion.snakeToCamel(pair.key)
            case .custom(let transform):
                decodedKey = transform(codingPath + [YAMLCodingKey(stringValue: pair.key)]).stringValue
            }
            if lookup[decodedKey] == nil { ordered.append(decodedKey) }
            lookup[decodedKey] = pair.value
        }
        self.lookup = lookup
        self.orderedKeys = ordered
    }

    var allKeys: [Key] { orderedKeys.compactMap { Key(stringValue: $0) } }

    func contains(_ key: Key) -> Bool { lookup[key.stringValue] != nil }

    private func value(for key: Key) throws -> YAMLValue {
        guard let value = lookup[key.stringValue] else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }
        return value
    }

    private func path(_ key: Key) -> [any CodingKey] { codingPath + [key] }

    func decodeNil(forKey key: Key) throws -> Bool {
        if case .null = try value(for: key) { return true }
        return false
    }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { try decoder.unboxBool(try value(for: key), at: path(key)) }
    func decode(_ type: String.Type, forKey key: Key) throws -> String { try decoder.unboxString(try value(for: key), at: path(key)) }
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try decoder.unboxDouble(try value(for: key), at: path(key)) }
    func decode(_ type: Float.Type, forKey key: Key) throws -> Float { try decoder.unboxFloat(try value(for: key), at: path(key)) }
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try decoder.unboxInteger(try value(for: key), as: Int.self, at: path(key)) }
    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try decoder.unboxInteger(try value(for: key), as: Int8.self, at: path(key)) }
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { try decoder.unboxInteger(try value(for: key), as: Int16.self, at: path(key)) }
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { try decoder.unboxInteger(try value(for: key), as: Int32.self, at: path(key)) }
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { try decoder.unboxInteger(try value(for: key), as: Int64.self, at: path(key)) }
    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try decoder.unboxInteger(try value(for: key), as: UInt.self, at: path(key)) }
    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { try decoder.unboxInteger(try value(for: key), as: UInt8.self, at: path(key)) }
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try decoder.unboxInteger(try value(for: key), as: UInt16.self, at: path(key)) }
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try decoder.unboxInteger(try value(for: key), as: UInt32.self, at: path(key)) }
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try decoder.unboxInteger(try value(for: key), as: UInt64.self, at: path(key)) }
    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T { try decoder.unbox(try value(for: key), as: type, at: path(key)) }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type, forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> {
        let value = try value(for: key)
        guard case .mapping(let mapping) = value else {
            throw decoder.typeMismatch([String: Any].self, value, at: path(key))
        }
        return KeyedDecodingContainer(
            YAMLKeyedDecodingContainer<NestedKey>(decoder: decoder, mapping: mapping, codingPath: path(key)))
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        let value = try value(for: key)
        guard case .sequence(let elements) = value else {
            throw decoder.typeMismatch([Any].self, value, at: path(key))
        }
        return YAMLUnkeyedDecodingContainer(decoder: decoder, elements: elements, codingPath: path(key))
    }

    func superDecoder() throws -> Decoder {
        try makeSuperDecoder(for: YAMLCodingKey.super)
    }

    func superDecoder(forKey key: Key) throws -> Decoder {
        try makeSuperDecoder(for: key)
    }

    private func makeSuperDecoder(for key: any CodingKey) throws -> Decoder {
        let value = lookup[key.stringValue] ?? .null
        return _YAMLDecoder(value: value, options: decoder.options, codingPath: codingPath + [key])
    }
}

// MARK: - Unkeyed decoding container

struct YAMLUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    private let decoder: _YAMLDecoder
    private let elements: [YAMLValue]
    let codingPath: [any CodingKey]
    private(set) var currentIndex: Int = 0

    init(decoder: _YAMLDecoder, elements: [YAMLValue], codingPath: [any CodingKey]) {
        self.decoder = decoder
        self.elements = elements
        self.codingPath = codingPath
    }

    var count: Int? { elements.count }
    var isAtEnd: Bool { currentIndex >= elements.count }

    private var currentPath: [any CodingKey] { codingPath + [YAMLCodingKey(intValue: currentIndex)] }

    private mutating func nextValue(_ type: Any.Type) throws -> YAMLValue {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(
                type,
                DecodingError.Context(
                    codingPath: currentPath,
                    debugDescription: "Unkeyed container is at end."))
        }
        let value = elements[currentIndex]
        return value
    }

    mutating func decodeNil() throws -> Bool {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(
                Any?.self,
                DecodingError.Context(codingPath: currentPath, debugDescription: "Unkeyed container is at end."))
        }
        if case .null = elements[currentIndex] {
            currentIndex += 1
            return true
        }
        return false
    }

    mutating func decode(_ type: Bool.Type) throws -> Bool { let v = try nextValue(type); let r = try decoder.unboxBool(v, at: currentPath); currentIndex += 1; return r }
    mutating func decode(_ type: String.Type) throws -> String { let v = try nextValue(type); let r = try decoder.unboxString(v, at: currentPath); currentIndex += 1; return r }
    mutating func decode(_ type: Double.Type) throws -> Double { let v = try nextValue(type); let r = try decoder.unboxDouble(v, at: currentPath); currentIndex += 1; return r }
    mutating func decode(_ type: Float.Type) throws -> Float { let v = try nextValue(type); let r = try decoder.unboxFloat(v, at: currentPath); currentIndex += 1; return r }
    mutating func decode(_ type: Int.Type) throws -> Int { let v = try nextValue(type); let r = try decoder.unboxInteger(v, as: Int.self, at: currentPath); currentIndex += 1; return r }
    mutating func decode(_ type: Int8.Type) throws -> Int8 { let v = try nextValue(type); let r = try decoder.unboxInteger(v, as: Int8.self, at: currentPath); currentIndex += 1; return r }
    mutating func decode(_ type: Int16.Type) throws -> Int16 { let v = try nextValue(type); let r = try decoder.unboxInteger(v, as: Int16.self, at: currentPath); currentIndex += 1; return r }
    mutating func decode(_ type: Int32.Type) throws -> Int32 { let v = try nextValue(type); let r = try decoder.unboxInteger(v, as: Int32.self, at: currentPath); currentIndex += 1; return r }
    mutating func decode(_ type: Int64.Type) throws -> Int64 { let v = try nextValue(type); let r = try decoder.unboxInteger(v, as: Int64.self, at: currentPath); currentIndex += 1; return r }
    mutating func decode(_ type: UInt.Type) throws -> UInt { let v = try nextValue(type); let r = try decoder.unboxInteger(v, as: UInt.self, at: currentPath); currentIndex += 1; return r }
    mutating func decode(_ type: UInt8.Type) throws -> UInt8 { let v = try nextValue(type); let r = try decoder.unboxInteger(v, as: UInt8.self, at: currentPath); currentIndex += 1; return r }
    mutating func decode(_ type: UInt16.Type) throws -> UInt16 { let v = try nextValue(type); let r = try decoder.unboxInteger(v, as: UInt16.self, at: currentPath); currentIndex += 1; return r }
    mutating func decode(_ type: UInt32.Type) throws -> UInt32 { let v = try nextValue(type); let r = try decoder.unboxInteger(v, as: UInt32.self, at: currentPath); currentIndex += 1; return r }
    mutating func decode(_ type: UInt64.Type) throws -> UInt64 { let v = try nextValue(type); let r = try decoder.unboxInteger(v, as: UInt64.self, at: currentPath); currentIndex += 1; return r }

    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let v = try nextValue(type)
        let r = try decoder.unbox(v, as: type, at: currentPath)
        currentIndex += 1
        return r
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type
    ) throws -> KeyedDecodingContainer<NestedKey> {
        let value = try nextValue([String: Any].self)
        guard case .mapping(let mapping) = value else {
            throw decoder.typeMismatch([String: Any].self, value, at: currentPath)
        }
        let container = YAMLKeyedDecodingContainer<NestedKey>(decoder: decoder, mapping: mapping, codingPath: currentPath)
        currentIndex += 1
        return KeyedDecodingContainer(container)
    }

    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        let value = try nextValue([Any].self)
        guard case .sequence(let elements) = value else {
            throw decoder.typeMismatch([Any].self, value, at: currentPath)
        }
        let container = YAMLUnkeyedDecodingContainer(decoder: decoder, elements: elements, codingPath: currentPath)
        currentIndex += 1
        return container
    }

    mutating func superDecoder() throws -> Decoder {
        let value = try nextValue(Decoder.self)
        let sub = _YAMLDecoder(value: value, options: decoder.options, codingPath: currentPath)
        currentIndex += 1
        return sub
    }
}
