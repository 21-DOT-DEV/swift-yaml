import YAML

// Shared Codable fixtures, authored from the data model (not from our own
// output), exercising the surface a real consumer hits: nested structs,
// arrays, dictionaries, optionals, enums (raw and associated-value), and class
// inheritance (which drives superEncoder/superDecoder).

struct Server: Codable, Equatable {
    var host: String
    var port: Int
    var tls: Bool
}

enum Color: String, Codable, Equatable {
    case red, green, blue
}

enum Shape: Codable, Equatable {
    case circle(radius: Double)
    case rectangle(width: Double, height: Double)
}

struct Config: Codable, Equatable {
    var name: String
    var version: Int
    var enabled: Bool
    var ratio: Double
    var servers: [Server]
    var tags: [String]
    var limits: [String: Int]
    var favorite: Color
    var note: String?
    var shapes: [Shape]
}

// A class hierarchy: encoding/decoding the subclass routes the superclass
// through superEncoder()/superDecoder() — the referencing-encoder path.
class Base: Codable, Equatable {
    var id: Int
    init(id: Int) { self.id = id }

    enum CodingKeys: String, CodingKey { case id }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
    }

    static func == (lhs: Base, rhs: Base) -> Bool { lhs.id == rhs.id }
}

final class Derived: Base {
    var label: String
    init(id: Int, label: String) {
        self.label = label
        super.init(id: id)
    }

    enum CodingKeys: String, CodingKey { case label }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        try super.init(from: container.superDecoder())
    }

    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(label, forKey: .label)
        try super.encode(to: container.superEncoder())
    }

    static func == (lhs: Derived, rhs: Derived) -> Bool {
        lhs.id == rhs.id && lhs.label == rhs.label
    }
}

extension Config {
    static let sample = Config(
        name: "edge",
        version: 3,
        enabled: true,
        ratio: 0.75,
        servers: [
            Server(host: "a.example.com", port: 80, tls: false),
            Server(host: "b.example.com", port: 443, tls: true),
        ],
        tags: ["primary", "us-east"],
        limits: ["cpu": 4, "mem": 16],
        favorite: .green,
        note: nil,
        shapes: [.circle(radius: 2.5), .rectangle(width: 3, height: 4)])
}
