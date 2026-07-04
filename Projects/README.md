# Projects/

Downstream example/reproduction packages that consume swift-yaml the way real
clients do. Kept out of the root `Package.swift` so the library package stays
lean and interop-free for its own consumers.

## InteropRepro

A minimal SwiftPM executable that imports the `YAML` product with C++ interop
enabled (`.interoperabilityMode(.Cxx)`) and round-trips a `Codable` value through
`YAMLDecoder` / `YAMLEncoder`.

Its purpose is to **reliably reproduce** the macOS-only C++-interop build failure
described below, and to serve as a regression guard.

```sh
# Reproduces the failure on the PRE-FIX library (whole-module compile):
swift build -c release --package-path Projects/InteropRepro
#   .../YAMLSerialization.swift:NN: error: no exact matches in call to initializer

# Passes on the fixed library, in every mode:
swift build --package-path Projects/InteropRepro                 # debug
swift build -c release --package-path Projects/InteropRepro      # release / whole-module
swift run  -c release --package-path Projects/InteropRepro       # runs the round-trip
```

### The upstream Swift interop bug this guards against

swift-yaml converts yaml-cpp's `std::string` values into Swift `String`s at its
C++-interop boundary. Doing so through the CxxStdlib overlay's
`String(_ cxxString: std.string)` initializer hits an upstream Swift compiler bug:
that initializer (and the `Cxx` module's `std.string` `Collection` conformance)
**drops out of overload resolution when `YAMLSerialization.swift` is type-checked in
the same frontend invocation as its sibling files** — i.e. under whole-module
compilation, or the multi-file batches the driver forms on a low-core host. The
result is `error: no exact matches in call to initializer` on `String(someStdString)`.

Because it depends on how the compiler *groups* a module's files:

- **Debug builds on a many-core machine** split the module ~one file per batch, so
  each file compiles alone and the overlay stays visible → **passes** locally.
- **A low-core CI runner** packs several files per batch → **fails**.
- **A `-c release` build** compiles the whole module as one unit → **fails on any
  macOS toolchain** (Swift 6.3 through 6.4 all reproduce).
- **Linux** uses a different `std::string → String` path and is unaffected → passes.

Closest upstream report: <https://forums.swift.org/t/std-string-to-string-in-release-builds/74393>
(Apple confirmed the same overload-visibility bug, there triggered by release/WMO).

### The fix

swift-yaml no longer lets a `std::string` cross into Swift. The `yamlcppShims` C++
helpers convert to a plain `const char*` + byte length and Swift reads that with
stdlib-only APIs — see `Sources/yamlcppShims/include/yamlcpp_shims.h` (the `CStr`
type) and `Sources/YAML/YAMLSerialization.swift`.

### Why CI uses `-c release`

A `-c release` build reproduces the failure on **any** macOS toolchain, so CI uses
it as the deterministic gate rather than relying on a runner's core count.
