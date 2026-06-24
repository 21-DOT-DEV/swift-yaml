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
    // Build-time-only DocC plugin, gated to untagged (development) checkouts —
    // see `developmentDependencies` below.
    dependencies: Package.Dependency.developmentDependencies,
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

// MARK: - Development-only dependencies

extension Package.Dependency {
    /// Dependencies needed only when working in this repo, excluded at tagged
    /// releases (mirrors swift-secp256k1's manifest gate).
    ///
    /// The sole entry is the DocC plugin: it is build-time only — it generates
    /// the hostable static site via `swift package generate-documentation` and
    /// is not a dependency of any product target, so it adds no code to what
    /// consumers link. Gating on an untagged checkout means that when swift-yaml
    /// is resolved at a release tag, `currentTag` is non-nil and consumers never
    /// fetch or resolve swift-docc-plugin; it is pulled in only for local docs
    /// work on an untagged checkout.
    static var developmentDependencies: [Package.Dependency] {
        guard Context.gitInformation?.currentTag == nil else { return [] }
        return [
            .package(url: "https://github.com/swiftlang/swift-docc-plugin", exact: "1.5.0")
        ]
    }
}
