// swift-tools-version: 6.1
import PackageDescription

// A downstream consumer that reproduces swift-yaml's macOS whole-module C++-interop
// failure.
//
// It imports the `YAML` product with C++ interop enabled. Building this package under
// `-c release` (or any whole-module / multi-file-batch compile) compiles the `YAML`
// dependency in whole-module mode — the configuration that deterministically triggers
//
//     error: no exact matches in call to initializer
//
// on swift-yaml's std::string → String conversions in the PRE-FIX library, and builds
// clean once the C-string boundary fix has landed.
//
// The underlying cause is an upstream Swift C++-interop bug: the CxxStdlib overlay's
// `String(_: std.string)` initializer drops out of overload resolution when a module's
// files are type-checked together (whole-module, or multi-file batches)
// — https://forums.swift.org/t/std-string-to-string-in-release-builds/74393. See
// ../README.md for the full diagnosis.
//
// It lives in its own package (not a target of the root manifest) so the library
// package stays interop-free for its own consumers.
let package = Package(
    name: "InteropRepro",
    dependencies: [
        // The package under test, by path — resolves to the repo root two levels up.
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "interop-repro",
            dependencies: [
                // Importing YAML pulls in C++ interop, which is viral to direct
                // importers — so any consumer target must enable .Cxx too.
                .product(name: "YAML", package: "swift-yaml")
            ],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        )
    ]
)
