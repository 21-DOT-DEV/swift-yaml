// The internal encoder and its storage. Per SE-0167, the public `YAMLEncoder`
// does not conform to `Encoder`; this internal type does, building a tree of
// reference nodes that `YAMLSerialization` then emits. Reference semantics
// (the `YAMLRef*` types) are what make `nestedContainer`/`superEncoder` work:
// a child container linked into its parent stays live, so writes after the link
// are still reflected when the tree resolves. This mirrors swift-foundation's
// `__JSONEncoder` (which uses `NSMutableArray`/`NSMutableDictionary` for the
// same reason).

// MARK: - Reference-typed in-progress tree

/// A node in the in-progress encoding tree: a finished value, or a still-mutable
/// child container linked live into its parent.
final class YAMLRefNode {
    enum Storage {
        case value(YAMLValue)
        case array(YAMLRefArray)
        case object(YAMLRefObject)
    }
    var storage: Storage
    init(_ storage: Storage) { self.storage = storage }
    static func value(_ value: YAMLValue) -> YAMLRefNode { YAMLRefNode(.value(value)) }

    var resolved: YAMLValue {
        switch storage {
        case .value(let v): return v
        case .array(let a): return a.resolved
        case .object(let o): return o.resolved
        }
    }
}

/// A mutable, insertion-ordered map node.
final class YAMLRefObject {
    private(set) var keys: [String] = []
    private var children: [String: YAMLRefNode] = [:]

    func set(_ node: YAMLRefNode, forKey key: String) {
        if children[key] == nil { keys.append(key) }
        children[key] = node
    }

    func setValue(_ value: YAMLValue, forKey key: String) {
        set(.value(value), forKey: key)
    }

    var resolved: YAMLValue {
        var mapping = YAMLMapping()
        for key in keys { mapping.set(children[key]!.resolved, forKey: key) }
        return .mapping(mapping)
    }
}

/// A mutable sequence node.
final class YAMLRefArray {
    private(set) var children: [YAMLRefNode] = []
    var count: Int { children.count }

    func append(_ node: YAMLRefNode) { children.append(node) }
    func appendValue(_ value: YAMLValue) { children.append(.value(value)) }
    func insert(_ node: YAMLRefNode, at index: Int) { children.insert(node, at: index) }

    var resolved: YAMLValue { .sequence(children.map { $0.resolved }) }
}

/// The encoder's stack of in-progress containers.
final class YAMLEncodingStorage {
    private(set) var nodes: [YAMLRefNode] = []
    var count: Int { nodes.count }
    var last: YAMLRefNode? { nodes.last }

    func pushKeyedContainer() -> YAMLRefObject {
        let object = YAMLRefObject()
        nodes.append(YAMLRefNode(.object(object)))
        return object
    }

    func pushUnkeyedContainer() -> YAMLRefArray {
        let array = YAMLRefArray()
        nodes.append(YAMLRefNode(.array(array)))
        return array
    }

    func push(_ value: YAMLValue) { nodes.append(.value(value)) }

    func popContainer() -> YAMLRefNode { nodes.removeLast() }
}

// MARK: - Internal encoder

// Not `final`: `_YAMLReferencingEncoder` subclasses it for `superEncoder`.
class _YAMLEncoder: Encoder, SingleValueEncodingContainer {
    let storage = YAMLEncodingStorage()
    var codingPath: [any CodingKey]
    let options: YAMLEncoderOptions

    var userInfo: [CodingUserInfoKey: Any] { options.userInfo.mapValues { $0 as Any } }

    init(options: YAMLEncoderOptions, codingPath: [any CodingKey] = []) {
        self.options = options
        self.codingPath = codingPath
    }

    /// A new value may be encoded only when the storage depth matches the path
    /// depth — the invariant that keeps exactly one value per container slot.
    var canEncodeNewValue: Bool { storage.count == codingPath.count }

    // MARK: Encoder

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        let object: YAMLRefObject
        if canEncodeNewValue {
            object = storage.pushKeyedContainer()
        } else if case .object(let existing)? = storage.last?.storage {
            object = existing
        } else {
            preconditionFailure("Cannot push a keyed container in this state")
        }
        return KeyedEncodingContainer(
            YAMLKeyedEncodingContainer<Key>(referencing: self, codingPath: codingPath, wrapping: object))
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        let array: YAMLRefArray
        if canEncodeNewValue {
            array = storage.pushUnkeyedContainer()
        } else if case .array(let existing)? = storage.last?.storage {
            array = existing
        } else {
            preconditionFailure("Cannot push an unkeyed container in this state")
        }
        return YAMLUnkeyedEncodingContainer(referencing: self, codingPath: codingPath, wrapping: array)
    }

    func singleValueContainer() -> SingleValueEncodingContainer { self }

    // MARK: SingleValueEncodingContainer

    private func assertCanEncodeNewValue() {
        precondition(
            canEncodeNewValue,
            "Attempt to encode value through single value container when previously value already encoded.")
    }

    func encodeNil() throws { assertCanEncodeNewValue(); storage.push(.null) }
    func encode(_ value: Bool) throws { assertCanEncodeNewValue(); storage.push(.bool(value)) }
    func encode(_ value: String) throws { assertCanEncodeNewValue(); storage.push(.string(value)) }
    func encode(_ value: Double) throws { assertCanEncodeNewValue(); storage.push(try boxDouble(value)) }
    func encode(_ value: Float) throws { assertCanEncodeNewValue(); storage.push(try boxFloat(value)) }
    func encode(_ value: Int) throws { assertCanEncodeNewValue(); storage.push(boxSigned(value)) }
    func encode(_ value: Int8) throws { assertCanEncodeNewValue(); storage.push(boxSigned(value)) }
    func encode(_ value: Int16) throws { assertCanEncodeNewValue(); storage.push(boxSigned(value)) }
    func encode(_ value: Int32) throws { assertCanEncodeNewValue(); storage.push(boxSigned(value)) }
    func encode(_ value: Int64) throws { assertCanEncodeNewValue(); storage.push(.int(value)) }
    func encode(_ value: UInt) throws { assertCanEncodeNewValue(); storage.push(boxUnsigned(value)) }
    func encode(_ value: UInt8) throws { assertCanEncodeNewValue(); storage.push(boxUnsigned(value)) }
    func encode(_ value: UInt16) throws { assertCanEncodeNewValue(); storage.push(boxUnsigned(value)) }
    func encode(_ value: UInt32) throws { assertCanEncodeNewValue(); storage.push(boxUnsigned(value)) }
    func encode(_ value: UInt64) throws { assertCanEncodeNewValue(); storage.push(.uint(value)) }

    func encode<T: Encodable>(_ value: T) throws {
        assertCanEncodeNewValue()
        storage.push(try boxEncodable(value))
    }

    // MARK: Boxing

    func boxSigned<T: BinaryInteger & SignedInteger>(_ value: T) -> YAMLValue { .int(Int64(value)) }
    func boxUnsigned<T: BinaryInteger & UnsignedInteger>(_ value: T) -> YAMLValue { .uint(UInt64(value)) }

    func boxDouble(_ value: Double) throws -> YAMLValue {
        if value.isFinite { return .double(value) }
        switch options.nonConformingFloat {
        case .nativeYAML:
            return .double(value)
        case .throw:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Unable to encode non-finite Double \(value); set nonConformingFloatEncodingStrategy to allow it."))
        case let .convertToString(positiveInfinity, negativeInfinity, nan):
            if value.isNaN { return .string(nan) }
            return .string(value > 0 ? positiveInfinity : negativeInfinity)
        }
    }

    func boxFloat(_ value: Float) throws -> YAMLValue {
        if value.isFinite { return .float(value) }
        switch options.nonConformingFloat {
        case .nativeYAML:
            return .float(value)
        case .throw:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Unable to encode non-finite Float \(value); set nonConformingFloatEncodingStrategy to allow it."))
        case let .convertToString(positiveInfinity, negativeInfinity, nan):
            if value.isNaN { return .string(nan) }
            return .string(value > 0 ? positiveInfinity : negativeInfinity)
        }
    }

    /// Boxes an arbitrary `Encodable`. Foundation special types (Date/Data) are
    /// handled in the gated `boxFoundation`; everything else runs its own
    /// `encode(to:)` against this encoder, unwinding the stack if it throws
    /// mid-encode (so a partial container never corrupts a later pop).
    func boxEncodable(_ value: Encodable) throws -> YAMLValue {
        #if canImport(FoundationEssentials) || canImport(Foundation)
        if let special = try boxFoundation(value) { return special }
        #endif
        return try boxViaEncodable(value)
    }

    func boxViaEncodable(_ value: Encodable) throws -> YAMLValue {
        let depth = storage.count
        do {
            try value.encode(to: self)
        } catch {
            if storage.count > depth { _ = storage.popContainer() }
            throw error
        }
        guard storage.count > depth else {
            // The value encoded nothing of its own; represent as an empty map.
            return .mapping(YAMLMapping())
        }
        return storage.popContainer().resolved
    }

    /// Applies the active key strategy to a coding key, returning the emitted
    /// mapping-key string.
    func encodedKey(_ key: any CodingKey, at path: [any CodingKey]) -> String {
        switch options.keyStrategy {
        case .useDefaultKeys:
            return key.stringValue
        case .convertToSnakeCase:
            return KeyStrategyConversion.camelToSnake(key.stringValue)
        case .custom(let transform):
            return transform(path + [key]).stringValue
        }
    }
}

// MARK: - Referencing encoder (superEncoder)

/// Subclass returned by `superEncoder()` / `superEncoder(forKey:)`. It builds
/// its own single-value storage and, in `deinit`, writes the result back into
/// the parent container slot.
final class _YAMLReferencingEncoder: _YAMLEncoder {
    enum Reference {
        case array(YAMLRefArray, Int)
        case object(YAMLRefObject, String)
    }

    let parent: _YAMLEncoder
    let reference: Reference

    init(referencing parent: _YAMLEncoder, at index: Int, wrapping array: YAMLRefArray) {
        self.parent = parent
        self.reference = .array(array, index)
        super.init(options: parent.options, codingPath: parent.codingPath)
        codingPath.append(YAMLCodingKey(intValue: index))
    }

    init(referencing parent: _YAMLEncoder, key: any CodingKey, convertedKey: String, wrapping object: YAMLRefObject) {
        self.parent = parent
        self.reference = .object(object, convertedKey)
        super.init(options: parent.options, codingPath: parent.codingPath)
        codingPath.append(key)
    }

    override var canEncodeNewValue: Bool {
        storage.count == codingPath.count - parent.codingPath.count - 1
    }

    deinit {
        let value: YAMLValue
        switch storage.count {
        case 0: value = .mapping(YAMLMapping())
        case 1: value = storage.popContainer().resolved
        default: preconditionFailure("Referencing encoder ended with multiple containers on the stack.")
        }
        switch reference {
        case let .array(array, index):
            if index <= array.count {
                array.insert(.value(value), at: index)
            } else {
                array.appendValue(value)
            }
        case let .object(object, key):
            object.setValue(value, forKey: key)
        }
    }
}
