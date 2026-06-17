// The internal intermediate representation that sits between Swift's `Codable`
// machinery and yaml-cpp. All `Encoder`/`Decoder` logic runs over this pure
// Swift tree; the C++ shims are touched at exactly two boundaries — parse
// (text → tree) and emit (tree → text) — in `YAMLSerialization`.
//
// Decoding produces `.null` / `.string` / `.sequence` / `.mapping`: YAML
// scalars are untyped text, resolved to a concrete Swift type only when a
// container is asked for one (the faithful YAML model). Encoding produces the
// typed cases so the serializer can format and quote each scalar correctly.
enum YAMLValue {
    case null
    case bool(Bool)
    case int(Int64)
    case uint(UInt64)
    case double(Double)
    case float(Float)
    case string(String)
    case sequence([YAMLValue])
    case mapping(YAMLMapping)
}

/// An insertion-ordered string-keyed map with O(1) lookup. Codable keyed
/// containers only ever address maps by string key (like `JSONEncoder`), so a
/// string-keyed model is exactly the needed surface.
struct YAMLMapping {
    private(set) var keys: [String]
    private(set) var values: [YAMLValue]
    private var index: [String: Int]

    init() {
        keys = []
        values = []
        index = [:]
    }

    init(keys: [String], values: [YAMLValue]) {
        self.keys = keys
        self.values = values
        var idx = [String: Int](minimumCapacity: keys.count)
        for (i, k) in keys.enumerated() where idx[k] == nil { idx[k] = i }
        self.index = idx
    }

    var count: Int { keys.count }

    func contains(_ key: String) -> Bool { index[key] != nil }

    subscript(_ key: String) -> YAMLValue? { index[key].map { values[$0] } }

    /// Sets `value` for `key`, preserving first-insertion order; an existing
    /// key is overwritten in place (last-wins).
    mutating func set(_ value: YAMLValue, forKey key: String) {
        if let i = index[key] {
            values[i] = value
        } else {
            index[key] = keys.count
            keys.append(key)
            values.append(value)
        }
    }

    var pairs: [(key: String, value: YAMLValue)] {
        zip(keys, values).map { (key: $0, value: $1) }
    }

    func sortedPairs() -> [(key: String, value: YAMLValue)] {
        pairs.sorted { $0.key < $1.key }
    }
}

/// A general-purpose `CodingKey` used internally for synthesized keys (the
/// `super` key, array indices, and strategy-remapped keys).
struct YAMLCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }

    init(stringValue: String, intValue: Int?) {
        self.stringValue = stringValue
        self.intValue = intValue
    }

    static let `super` = YAMLCodingKey(stringValue: "super")
}
