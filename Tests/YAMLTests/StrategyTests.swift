import Testing
import YAML
import Foundation

@Suite struct Strategies {

    struct CamelCased: Codable, Equatable {
        var firstName: String
        var lastNameValue: String
    }

    @Test func convertToSnakeCaseEmitsSnakeKeys() throws {
        let encoder = YAMLEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let yaml = try encoder.encode(CamelCased(firstName: "Ada", lastNameValue: "Lovelace"))
        #expect(yaml.contains("first_name"))
        #expect(yaml.contains("last_name_value"))
    }

    @Test func convertFromSnakeCaseReadsSnakeKeys() throws {
        let decoder = YAMLDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(CamelCased.self, from: "first_name: Ada\nlast_name_value: Lovelace")
        #expect(decoded == CamelCased(firstName: "Ada", lastNameValue: "Lovelace"))
    }

    @Test func snakeCaseRoundTrips() throws {
        let encoder = YAMLEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        let decoder = YAMLDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let original = CamelCased(firstName: "Grace", lastNameValue: "Hopper")
        let decoded = try decoder.decode(CamelCased.self, from: encoder.encode(original))
        #expect(decoded == original)
    }

    @Test func sortedKeysAreOrdered() throws {
        let encoder = YAMLEncoder()
        encoder.outputFormatting = .sortedKeys
        let yaml = try encoder.encode(["charlie": 3, "alpha": 1, "bravo": 2])
        let alpha = yaml.range(of: "alpha")!
        let bravo = yaml.range(of: "bravo")!
        let charlie = yaml.range(of: "charlie")!
        #expect(alpha.lowerBound < bravo.lowerBound)
        #expect(bravo.lowerBound < charlie.lowerBound)
    }

    @Test func flowStyleEmitsInline() throws {
        let encoder = YAMLEncoder()
        encoder.outputFormatting = .flowStyle
        let yaml = try encoder.encode(Server(host: "h", port: 1, tls: false))
        #expect(yaml.contains("{"))
        #expect(yaml.contains("}"))
    }

    @Test func indentWidthIsHonored() throws {
        struct Wrapper: Codable { var inner: Server }
        let encoder = YAMLEncoder()
        encoder.indent = 4
        let yaml = try encoder.encode(Wrapper(inner: Server(host: "h", port: 1, tls: false)))
        #expect(yaml.contains("    "))  // four-space indent appears
    }

    @Test func nonConformingFloatNativeRoundTrips() throws {
        struct Floats: Codable, Equatable {
            var pos: Double
            var neg: Double
            var nan: Double
            static func == (l: Floats, r: Floats) -> Bool {
                l.pos == r.pos && l.neg == r.neg && l.nan.isNaN == r.nan.isNaN
            }
        }
        let value = Floats(pos: .infinity, neg: -.infinity, nan: .nan)
        let yaml = try YAMLEncoder().encode(value)
        #expect(yaml.contains(".inf"))
        #expect(yaml.contains(".nan"))
        let decoded = try YAMLDecoder().decode(Floats.self, from: yaml)
        #expect(decoded == value)
    }

    @Test func nonConformingFloatThrowStrategyThrows() throws {
        let encoder = YAMLEncoder()
        encoder.nonConformingFloatEncodingStrategy = .throw
        #expect(throws: EncodingError.self) {
            _ = try encoder.encode([Double.infinity])
        }
    }

    @Test func iso8601DateRoundTrips() throws {
        struct Event: Codable, Equatable { var at: Date }
        // Whole-second instant so the ISO-8601 (no fractional) round-trip is exact.
        let event = Event(at: Date(timeIntervalSince1970: 1_700_000_000))
        let yaml = try YAMLEncoder().encode(event)
        #expect(yaml.contains("2023-11-14T"))
        let decoded = try YAMLDecoder().decode(Event.self, from: yaml)
        #expect(decoded == event)
    }

    @Test func secondsSince1970DateRoundTrips() throws {
        struct Event: Codable, Equatable { var at: Date }
        let encoder = YAMLEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = YAMLDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        let event = Event(at: Date(timeIntervalSince1970: 1_700_000_000.5))
        let decoded = try decoder.decode(Event.self, from: encoder.encode(event))
        #expect(decoded == event)
    }

    @Test func base64DataRoundTrips() throws {
        struct Blob: Codable, Equatable { var bytes: Data }
        let blob = Blob(bytes: Data([0, 1, 2, 250, 255]))
        let yaml = try YAMLEncoder().encode(blob)
        let decoded = try YAMLDecoder().decode(Blob.self, from: yaml)
        #expect(decoded == blob)
    }

    @Test func userInfoReachesDecoder() throws {
        let key = CodingUserInfoKey(rawValue: "tenant")!
        struct UsesUserInfo: Decodable {
            let tenant: String
            init(from decoder: Decoder) throws {
                tenant = decoder.userInfo[CodingUserInfoKey(rawValue: "tenant")!] as? String ?? "none"
            }
        }
        let decoder = YAMLDecoder()
        decoder.userInfo[key] = "acme"
        let value = try decoder.decode(UsesUserInfo.self, from: "{}")
        #expect(value.tenant == "acme")
    }
}
