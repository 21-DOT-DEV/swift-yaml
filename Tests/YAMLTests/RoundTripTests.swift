import Testing
import YAML

@Suite struct RoundTrip {
    let encoder = YAMLEncoder()
    let decoder = YAMLDecoder()

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let yaml = try encoder.encode(value)
        return try decoder.decode(T.self, from: yaml)
    }

    @Test func scalarsRoundTrip() throws {
        #expect(try roundTrip(42) == 42)
        #expect(try roundTrip("hello world") == "hello world")
        #expect(try roundTrip(true) == true)
        #expect(try roundTrip(3.14159) == 3.14159)
        #expect(try roundTrip(Float(0.1)) == Float(0.1))   // .float keeps Float precision
        #expect(try roundTrip(Int64.max) == Int64.max)
        #expect(try roundTrip(UInt64.max) == UInt64.max)    // exceeds Int64 — needs .uint
    }

    @Test func stringsThatLookLikeOtherTypesStayStrings() throws {
        // The quoting heuristic must keep these typed as String through a round-trip.
        for tricky in ["123", "3.14", "true", "false", "null", "~", "yes", "no", "", " padded "] {
            #expect(try roundTrip(tricky) == tricky, "round-trip failed for \(tricky.debugDescription)")
        }
    }

    @Test func nestedStructRoundTrips() throws {
        #expect(try roundTrip(Config.sample) == Config.sample)
    }

    @Test func arraysAndDictionariesRoundTrip() throws {
        #expect(try roundTrip([1, 2, 3]) == [1, 2, 3])
        #expect(try roundTrip(["a": 1, "b": 2]) == ["a": 1, "b": 2])
        #expect(try roundTrip([[1, 2], [3, 4]]) == [[1, 2], [3, 4]])
    }

    @Test func optionalsRoundTrip() throws {
        struct Box: Codable, Equatable { var value: Int? }
        #expect(try roundTrip(Box(value: 5)) == Box(value: 5))
        #expect(try roundTrip(Box(value: nil)) == Box(value: nil))
    }

    @Test func explicitNilInArrayRoundTrips() throws {
        // The encodeNil/decodeNil contract: a nil nested in an array must
        // round-trip as an explicit null, not be dropped (which would shift it).
        let values: [Int?] = [1, nil, 3]
        let yaml = try encoder.encode(values)
        let decoded = try decoder.decode([Int?].self, from: yaml)
        #expect(decoded == values)
    }

    @Test func rawEnumRoundTrips() throws {
        #expect(try roundTrip(Color.blue) == Color.blue)
    }

    @Test func associatedValueEnumRoundTrips() throws {
        #expect(try roundTrip(Shape.circle(radius: 9)) == Shape.circle(radius: 9))
        #expect(try roundTrip(Shape.rectangle(width: 1.5, height: 2.5)) == Shape.rectangle(width: 1.5, height: 2.5))
    }

    @Test func classInheritanceRoundTrips() throws {
        // Exercises superEncoder()/superDecoder() — the referencing encoder.
        let original = Derived(id: 7, label: "leaf")
        let yaml = try encoder.encode(original)
        let decoded = try decoder.decode(Derived.self, from: yaml)
        #expect(decoded == original)
    }

    @Test func deeplyNestedRoundTrips() throws {
        struct Tree: Codable, Equatable { var name: String; var children: [Tree] }
        let tree = Tree(name: "root", children: [
            Tree(name: "a", children: [Tree(name: "a1", children: [])]),
            Tree(name: "b", children: []),
        ])
        #expect(try roundTrip(tree) == tree)
    }
}
