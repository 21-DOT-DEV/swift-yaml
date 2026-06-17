// The keyed and unkeyed encoding containers. Scalars are written straight into
// the reference tree; nested containers link a live child ref (so later writes
// are reflected); full sub-values go through the encoder's box (which uses the
// storage stack). Coding-path push/restore uses inline append + `defer`, never
// a closure capturing the encoder (swift-corelibs-foundation PR #1512).

struct YAMLKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    private let encoder: _YAMLEncoder
    private let object: YAMLRefObject
    let codingPath: [any CodingKey]

    init(referencing encoder: _YAMLEncoder, codingPath: [any CodingKey], wrapping object: YAMLRefObject) {
        self.encoder = encoder
        self.codingPath = codingPath
        self.object = object
    }

    private func mapKey(_ key: Key) -> String { encoder.encodedKey(key, at: codingPath) }

    mutating func encodeNil(forKey key: Key) throws { object.setValue(.null, forKey: mapKey(key)) }
    mutating func encode(_ value: Bool, forKey key: Key) throws { object.setValue(.bool(value), forKey: mapKey(key)) }
    mutating func encode(_ value: String, forKey key: Key) throws { object.setValue(.string(value), forKey: mapKey(key)) }
    mutating func encode(_ value: Int, forKey key: Key) throws { object.setValue(encoder.boxSigned(value), forKey: mapKey(key)) }
    mutating func encode(_ value: Int8, forKey key: Key) throws { object.setValue(encoder.boxSigned(value), forKey: mapKey(key)) }
    mutating func encode(_ value: Int16, forKey key: Key) throws { object.setValue(encoder.boxSigned(value), forKey: mapKey(key)) }
    mutating func encode(_ value: Int32, forKey key: Key) throws { object.setValue(encoder.boxSigned(value), forKey: mapKey(key)) }
    mutating func encode(_ value: Int64, forKey key: Key) throws { object.setValue(.int(value), forKey: mapKey(key)) }
    mutating func encode(_ value: UInt, forKey key: Key) throws { object.setValue(encoder.boxUnsigned(value), forKey: mapKey(key)) }
    mutating func encode(_ value: UInt8, forKey key: Key) throws { object.setValue(encoder.boxUnsigned(value), forKey: mapKey(key)) }
    mutating func encode(_ value: UInt16, forKey key: Key) throws { object.setValue(encoder.boxUnsigned(value), forKey: mapKey(key)) }
    mutating func encode(_ value: UInt32, forKey key: Key) throws { object.setValue(encoder.boxUnsigned(value), forKey: mapKey(key)) }
    mutating func encode(_ value: UInt64, forKey key: Key) throws { object.setValue(.uint(value), forKey: mapKey(key)) }

    mutating func encode(_ value: Double, forKey key: Key) throws {
        encoder.codingPath.append(key)
        defer { encoder.codingPath.removeLast() }
        object.setValue(try encoder.boxDouble(value), forKey: mapKey(key))
    }

    mutating func encode(_ value: Float, forKey key: Key) throws {
        encoder.codingPath.append(key)
        defer { encoder.codingPath.removeLast() }
        object.setValue(try encoder.boxFloat(value), forKey: mapKey(key))
    }

    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
        encoder.codingPath.append(key)
        defer { encoder.codingPath.removeLast() }
        object.setValue(try encoder.boxEncodable(value), forKey: mapKey(key))
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy keyType: NestedKey.Type, forKey key: Key
    ) -> KeyedEncodingContainer<NestedKey> {
        let nested = YAMLRefObject()
        object.set(YAMLRefNode(.object(nested)), forKey: mapKey(key))
        return KeyedEncodingContainer(
            YAMLKeyedEncodingContainer<NestedKey>(referencing: encoder, codingPath: codingPath + [key], wrapping: nested))
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        let nested = YAMLRefArray()
        object.set(YAMLRefNode(.array(nested)), forKey: mapKey(key))
        return YAMLUnkeyedEncodingContainer(referencing: encoder, codingPath: codingPath + [key], wrapping: nested)
    }

    mutating func superEncoder() -> Encoder {
        _YAMLReferencingEncoder(referencing: encoder, key: YAMLCodingKey.super, convertedKey: "super", wrapping: object)
    }

    mutating func superEncoder(forKey key: Key) -> Encoder {
        _YAMLReferencingEncoder(referencing: encoder, key: key, convertedKey: mapKey(key), wrapping: object)
    }
}

struct YAMLUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    private let encoder: _YAMLEncoder
    private let array: YAMLRefArray
    let codingPath: [any CodingKey]

    init(referencing encoder: _YAMLEncoder, codingPath: [any CodingKey], wrapping array: YAMLRefArray) {
        self.encoder = encoder
        self.codingPath = codingPath
        self.array = array
    }

    var count: Int { array.count }

    private var indexKey: YAMLCodingKey { YAMLCodingKey(intValue: array.count) }

    mutating func encodeNil() throws { array.appendValue(.null) }
    mutating func encode(_ value: Bool) throws { array.appendValue(.bool(value)) }
    mutating func encode(_ value: String) throws { array.appendValue(.string(value)) }
    mutating func encode(_ value: Int) throws { array.appendValue(encoder.boxSigned(value)) }
    mutating func encode(_ value: Int8) throws { array.appendValue(encoder.boxSigned(value)) }
    mutating func encode(_ value: Int16) throws { array.appendValue(encoder.boxSigned(value)) }
    mutating func encode(_ value: Int32) throws { array.appendValue(encoder.boxSigned(value)) }
    mutating func encode(_ value: Int64) throws { array.appendValue(.int(value)) }
    mutating func encode(_ value: UInt) throws { array.appendValue(encoder.boxUnsigned(value)) }
    mutating func encode(_ value: UInt8) throws { array.appendValue(encoder.boxUnsigned(value)) }
    mutating func encode(_ value: UInt16) throws { array.appendValue(encoder.boxUnsigned(value)) }
    mutating func encode(_ value: UInt32) throws { array.appendValue(encoder.boxUnsigned(value)) }
    mutating func encode(_ value: UInt64) throws { array.appendValue(.uint(value)) }

    mutating func encode(_ value: Double) throws {
        encoder.codingPath.append(indexKey)
        defer { encoder.codingPath.removeLast() }
        array.appendValue(try encoder.boxDouble(value))
    }

    mutating func encode(_ value: Float) throws {
        encoder.codingPath.append(indexKey)
        defer { encoder.codingPath.removeLast() }
        array.appendValue(try encoder.boxFloat(value))
    }

    mutating func encode<T: Encodable>(_ value: T) throws {
        encoder.codingPath.append(indexKey)
        defer { encoder.codingPath.removeLast() }
        array.appendValue(try encoder.boxEncodable(value))
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy keyType: NestedKey.Type
    ) -> KeyedEncodingContainer<NestedKey> {
        let index = array.count
        let nested = YAMLRefObject()
        array.append(YAMLRefNode(.object(nested)))
        return KeyedEncodingContainer(
            YAMLKeyedEncodingContainer<NestedKey>(
                referencing: encoder, codingPath: codingPath + [YAMLCodingKey(intValue: index)], wrapping: nested))
    }

    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        let index = array.count
        let nested = YAMLRefArray()
        array.append(YAMLRefNode(.array(nested)))
        return YAMLUnkeyedEncodingContainer(
            referencing: encoder, codingPath: codingPath + [YAMLCodingKey(intValue: index)], wrapping: nested)
    }

    mutating func superEncoder() -> Encoder {
        _YAMLReferencingEncoder(referencing: encoder, at: array.count, wrapping: array)
    }
}
