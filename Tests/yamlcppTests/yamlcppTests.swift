import Testing
import yamlcppShims  // re-exports the vendored yamlcpp module (YAML.Load / Dump / ...)

// Inputs are YAML 1.2 spec examples lifted from yaml-cpp's own
// test/specexamples.h (examples 2.1 and 2.2) — the authoritative corpus
// upstream ships, cited rather than fabricated.

@Suite struct ParseAndEmit {
    // spec example 2.1 — a sequence of scalars.
    static let sequenceYAML = """
        - Mark McGwire
        - Sammy Sosa
        - Ken Griffey
        """

    // spec example 2.2 — a map of scalar values.
    static let mappingYAML = """
        hr:  65    # Home runs
        avg: 0.278 # Batting average
        rbi: 147   # Runs Batted In
        """

    @Test func parsesSequenceStructure() {
        let root = Self.sequenceYAML.withCString { YAML.Load($0) }
        #expect(root.IsSequence())
        #expect(root.size() == 3)
    }

    @Test func parsesMappingStructure() {
        let root = Self.mappingYAML.withCString { YAML.Load($0) }
        #expect(root.IsMap())
        #expect(root.size() == 3)
    }

    @Test func extractsTypedScalars() {
        let root = Self.mappingYAML.withCString { YAML.Load($0) }
        #expect(yamlx.asInt(yamlx.at(root, "hr")) == 65)
        #expect(yamlx.asInt(yamlx.at(root, "rbi")) == 147)
    }

    @Test func scalarTextRoundTrips() {
        let root = Self.sequenceYAML.withCString { YAML.Load($0) }
        #expect(String(yamlx.asString(yamlx.atIndex(root, 0))) == "Mark McGwire")
    }

    @Test func emitsParsedDocument() {
        let root = Self.sequenceYAML.withCString { YAML.Load($0) }
        #expect(String(YAML.Dump(root)).contains("Mark McGwire"))
    }
}
