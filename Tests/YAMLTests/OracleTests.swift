import Testing
import YAML
import yamlcppShims  // the independent reference: yaml-cpp's own parser
import Foundation    // the independent reference: JSONDecoder/JSONEncoder

// The same overlay-independent `String(_: yamlx.CStr)` conversion the overlay defines
// (see YAMLSerialization). YAMLTests is a separate module, so it carries its own copy —
// letting the oracle checks read yaml-cpp scalar text without the CxxStdlib overlay, so
// they also compile under whole-module mode.
extension String {
    init(_ view: yamlx.CStr) {
        guard let base = view.data, view.len > 0 else { self = ""; return }
        self = String(decoding: UnsafeRawBufferPointer(start: UnsafeRawPointer(base), count: view.len), as: UTF8.self)
    }
}

// Correctness is proven against checks that do NOT share our implementation:
// (1) re-parse our emitter's output through yaml-cpp — a different code path
// than our event-streamed emit; (2) decode the same data model from YAML and
// from JSON and require the same Swift values.
@Suite struct Oracle {

    // MARK: Re-parse through yaml-cpp

    @Test func emittedMappingReparsesInYAMLCpp() throws {
        let yaml = try YAMLEncoder().encode(Server(host: "localhost", port: 8080, tls: true))
        let result = yaml.withCString { yamlx.parse($0) }
        #expect(result.ok)
        #expect(yamlx.nodeKind(result.root) == 4)  // map
        #expect(String(yamlx.scalarText(yamlx.at(result.root, "host"))) == "localhost")
        #expect(String(yamlx.scalarText(yamlx.at(result.root, "port"))) == "8080")
        #expect(String(yamlx.scalarText(yamlx.at(result.root, "tls"))) == "true")
    }

    @Test func emittedSequenceReparsesInYAMLCpp() throws {
        let yaml = try YAMLEncoder().encode([10, 20, 30])
        let result = yaml.withCString { yamlx.parse($0) }
        #expect(result.ok)
        #expect(yamlx.nodeKind(result.root) == 3)  // sequence
        #expect(yamlx.count(result.root) == 3)
        #expect(String(yamlx.scalarText(yamlx.seqItem(result.root, 1))) == "20")
    }

    @Test func emittedStringScalarReparsesAsScalarNotNullOrNumber() throws {
        // A String "123" must come back as a scalar, and a String "null" must
        // NOT come back as a yaml-cpp Null node — the quoting did its job.
        struct Box: Codable { var a: String; var b: String }
        let yaml = try YAMLEncoder().encode(Box(a: "123", b: "null"))
        let result = yaml.withCString { yamlx.parse($0) }
        #expect(result.ok)
        #expect(yamlx.nodeKind(yamlx.at(result.root, "a")) == 2)  // scalar, not interpreted
        #expect(yamlx.nodeKind(yamlx.at(result.root, "b")) == 2)  // scalar, not Null(1)
        #expect(String(yamlx.scalarText(yamlx.at(result.root, "b"))) == "null")
    }

    // MARK: Agreement with Foundation's JSON codecs on the shared model

    @Test func decoderAgreesWithJSONDecoder() throws {
        let yaml = """
            host: example.com
            port: 443
            tls: true
            """
        let json = #"{"host": "example.com", "port": 443, "tls": true}"#
        let fromYAML = try YAMLDecoder().decode(Server.self, from: yaml)
        let fromJSON = try JSONDecoder().decode(Server.self, from: Data(json.utf8))
        #expect(fromYAML == fromJSON)
    }

    @Test func complexModelAgreesAcrossYAMLAndJSON() throws {
        // Encode with both codecs, decode with both, require identical values.
        let original = Config.sample
        let yaml = try YAMLEncoder().encode(original)
        let jsonData = try JSONEncoder().encode(original)
        let viaYAML = try YAMLDecoder().decode(Config.self, from: yaml)
        let viaJSON = try JSONDecoder().decode(Config.self, from: jsonData)
        #expect(viaYAML == original)
        #expect(viaYAML == viaJSON)
    }

    @Test func numbersAgreeWithJSON() throws {
        struct Numbers: Codable, Equatable {
            var i: Int
            var big: UInt64
            var d: Double
            var negative: Int
        }
        let yaml = """
            i: 0
            big: 18446744073709551615
            d: 2.5
            negative: -17
            """
        let json = #"{"i": 0, "big": 18446744073709551615, "d": 2.5, "negative": -17}"#
        let fromYAML = try YAMLDecoder().decode(Numbers.self, from: yaml)
        let fromJSON = try JSONDecoder().decode(Numbers.self, from: Data(json.utf8))
        #expect(fromYAML == fromJSON)
        #expect(fromYAML.big == .max)
    }
}
