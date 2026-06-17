// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "swift-yaml",
    products: [
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
        // instantiate from Swift. Created on demand from the smoke test's build
        // diagnostics — see Sources/yamlcppShims/include/yamlcpp_shims.h.
        .target(
            name: "yamlcppShims",
            dependencies: ["yamlcpp"]
        ),
        // Swift smoke tests. C++ interop is enabled here only: it is viral to
        // every downstream dependent and semver-major, so it stays on this leaf
        // and never on the library product above. The shims module re-exports
        // yamlcpp, so this single dependency reaches both surfaces.
        .testTarget(
            name: "yamlcppTests",
            dependencies: ["yamlcppShims"],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
    ],
    cxxLanguageStandard: .cxx11
)
