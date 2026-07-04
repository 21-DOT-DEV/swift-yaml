import YAML

// A downstream consumer that round-trips a Codable value through YAMLDecoder and
// YAMLEncoder — the public surface any client uses. Both decode and encode cross
// swift-yaml's std::string boundary in YAMLSerialization, the exact site that fails
// to compile under whole-module mode on the pre-fix library. If this target builds
// and runs, the C++-interop string boundary is sound.

struct ServerConfig: Codable, Equatable {
    var host: String
    var port: Int
    var tls: Bool
    var tags: [String]
}

let source = """
    host: localhost
    port: 8080
    tls: true
    tags: [alpha, beta]
    """

let decoder = YAMLDecoder()
let encoder = YAMLEncoder()

let decoded = try decoder.decode(ServerConfig.self, from: source)
let yaml = try encoder.encode(decoded)
let roundTrip = try decoder.decode(ServerConfig.self, from: yaml)

precondition(roundTrip == decoded, "round-trip mismatch: \(decoded) vs \(roundTrip)")

print("interop-repro OK — round-tripped \(decoded)")
print("--- re-encoded ---")
print(yaml, terminator: "")
