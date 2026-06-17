// snake_case ⇄ camelCase conversion for key strategies, in pure Swift so the
// codec core stays Foundation-free (Foundation's own converters live behind
// CharacterSet/NSString APIs we deliberately avoid — Yams#358). Behavior
// matches `JSONEncoder.KeyEncodingStrategy.convertToSnakeCase` /
// `JSONDecoder.KeyDecodingStrategy.convertFromSnakeCase` for the common cases,
// including acronym boundaries.
enum KeyStrategyConversion {

    /// `myURLValue` → `my_url_value`, `oneTwoThree` → `one_two_three`.
    static func camelToSnake(_ key: String) -> String {
        guard !key.isEmpty else { return key }
        let chars = Array(key)
        var words: [[Character]] = []
        var current: [Character] = []

        for i in chars.indices {
            let c = chars[i]
            if c.isUppercase, !current.isEmpty {
                let prev = current[current.count - 1]
                let nextIsLower = (i + 1 < chars.count) && chars[i + 1].isLowercase
                // Boundary after a lowercase/digit run, or at the tail of an
                // acronym that begins a new word (e.g. the V in "URLValue").
                if prev.isLowercase || prev.isNumber || (prev.isUppercase && nextIsLower) {
                    words.append(current)
                    current = []
                }
            }
            current.append(c)
        }
        if !current.isEmpty { words.append(current) }

        return words.map { String($0).lowercased() }.joined(separator: "_")
    }

    /// `one_two_three` → `oneTwoThree`, preserving leading/trailing underscores.
    static func snakeToCamel(_ key: String) -> String {
        guard key.contains("_") else { return key }

        let leadingCount = key.prefix { $0 == "_" }.count
        let trailingCount = key.reversed().prefix { $0 == "_" }.count
        guard leadingCount + trailingCount < key.count else { return key }  // all underscores

        let leading = String(repeating: "_", count: leadingCount)
        let trailing = String(repeating: "_", count: trailingCount)
        let core = key.dropFirst(leadingCount).dropLast(trailingCount)

        let parts = core.split(separator: "_", omittingEmptySubsequences: false)
        var result = ""
        for (idx, part) in parts.enumerated() {
            if part.isEmpty {
                result += "_"  // internal "__" run
            } else if idx == 0 {
                result += part.lowercased()
            } else {
                result += part.prefix(1).uppercased() + part.dropFirst()
            }
        }
        return leading + result + trailing
    }
}
