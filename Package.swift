// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "swift-yaml",
    products: [
        // The idiomatic Swift product: YAMLEncoder / YAMLDecoder + Codable.
        // Consumers `import YAML`. Because it rides the C++-interop shims, every
        // consuming target must enable .interoperabilityMode(.Cxx) — this is
        // viral and semver-major, the accepted cost of a C++-only upstream.
        .library(name: "YAML", targets: ["YAML"]),
        // The vendored C++ library. Consumers link this and opt into C++
        // interop on their own targets; the product itself ships interop-free.
        .library(name: "yamlcpp", targets: ["yamlcpp"]),
    ],
    targets: [
        // Vendored yaml-cpp (C++). Automatic source discovery compiles
        // everything under src/; public headers live in include/ (SwiftPM
        // synthesizes the C++ module map from it).
        .target(
            name: "yamlcpp",
            exclude: ["legal"]  // upstream LICENSE — attribution only, never compiled
            // No cxxSettings: quoted includes resolve relative to the including
            // file (src/ and src/contrib/ each include their own siblings) and
            // public headers propagate from include/ — so no headerSearchPath is
            // needed. Don't add one.
        ),
        // Authored C++ bridges for yaml-cpp's template-shaped surface
        // (operator[]<Key>, Node::as<T>()), which Swift C++ interop cannot
        // instantiate from Swift, plus the value-returning, exception-guarded
        // codec helpers the YAML overlay builds on (parse, node inspection,
        // event-streamed emitter). See Sources/yamlcppShims/include/yamlcpp_shims.h.
        .target(
            name: "yamlcppShims",
            dependencies: ["yamlcpp"]
        ),
        // The idiomatic Swift overlay. Builds ON the shims (Path B): it imports
        // yamlcppShims (which re-exports the vendored umbrella) and enables C++
        // interop. No hand-rolled C-ABI bridge — it reuses the yamlx:: helpers
        // exactly as the smoke test does.
        .target(
            name: "YAML",
            dependencies: ["yamlcppShims"],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
        // Swift smoke tests for the wrap. C++ interop is enabled here only: it
        // is viral to every downstream dependent and semver-major, so it stays
        // on this leaf and never on the library product above. The shims module
        // re-exports yamlcpp, so this single dependency reaches both surfaces.
        .testTarget(
            name: "yamlcppTests",
            dependencies: ["yamlcppShims"],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
        // Tests for the YAML overlay. Enables .Cxx (mirrors the wrap's smoke
        // test) so the cross-check can re-parse our output through yaml-cpp —
        // an independent code path from our emitter.
        .testTarget(
            name: "YAMLTests",
            dependencies: ["YAML", "yamlcppShims"],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
    ],
    cxxLanguageStandard: .cxx11
)
