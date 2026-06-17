import Testing
import YAML
import Foundation

// Proposal conformance: every public type, property, and method named in the
// approved API-PROPOSAL.md exists with the promised signature. This is a
// compile-time contract first; the assertions just keep it exercised.
@Suite struct APIConformance {

    @Test func encoderSurfaceExists() throws {
        let encoder = YAMLEncoder()
        encoder.indent = 2
        encoder.outputFormatting = [.sortedKeys, .flowStyle]
        encoder.keyEncodingStrategy = .useDefaultKeys
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.keyEncodingStrategy = .custom { $0.last! }
        encoder.nonConformingFloatEncodingStrategy = .nativeYAML
        encoder.nonConformingFloatEncodingStrategy = .throw
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Inf", negativeInfinity: "-Inf", nan: "NaN")
        encoder.dateEncodingStrategy = .iso8601
        encoder.dataEncodingStrategy = .base64
        encoder.userInfo[CodingUserInfoKey(rawValue: "k")!] = "v"
        let yaml: String = try encoder.encode(["k": 1])
        #expect(!yaml.isEmpty)
    }

    @Test func decoderSurfaceExists() throws {
        let decoder = YAMLDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.keyDecodingStrategy = .custom { $0.last! }
        decoder.nonConformingFloatDecodingStrategy = .nativeYAML
        decoder.nonConformingFloatDecodingStrategy = .throw
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Inf", negativeInfinity: "-Inf", nan: "NaN")
        decoder.duplicateKeyStrategy = .useLast
        decoder.duplicateKeyStrategy = .useFirst
        decoder.documentLimits = .default
        decoder.documentLimits = .unbounded
        decoder.documentLimits = YAMLDecoder.DocumentLimits(maxDepth: 10, maxNodeCount: 100, maxInputBytes: 1000)
        decoder.dateDecodingStrategy = .iso8601
        decoder.dataDecodingStrategy = .base64
        decoder.userInfo[CodingUserInfoKey(rawValue: "k")!] = "v"

        let fromString = try decoder.decode([String: Int].self, from: "k: 1")
        let fromBytes = try decoder.decode([String: Int].self, from: Array("k: 1".utf8))
        let fromData = try decoder.decode([String: Int].self, from: Data("k: 1".utf8))
        #expect(fromString == ["k": 1])
        #expect(fromBytes == ["k": 1])
        #expect(fromData == ["k": 1])
    }

    @Test func errorTypeIsPublicAndDescribable() {
        let error = YAMLError.parse(message: "boom", line: 3, column: 7)
        #expect(error.description.contains("line 3"))
        #expect(error.description.contains("column 7"))
    }
}
