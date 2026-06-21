# Getting Started with swift-yaml

@Metadata {
    @TitleHeading("Tutorial")
}

Add swift-yaml to a package, enable the required C++ interoperability setting, and round-trip your first `Codable` value through YAML.

## Overview

By the end of this guide you will have ``YAMLEncoder`` turning a Swift value into YAML text and ``YAMLDecoder`` reading it back — the same shape of code you would write with Foundation's `JSONEncoder` and `JSONDecoder`. The one step that has no JSON equivalent is enabling C++ interop, because the library is built on the vendored [yaml-cpp](https://github.com/jbeder/yaml-cpp) engine; do it once and the rest is ordinary `Codable`.

### Prerequisites

- A Swift 6.0+ toolchain and a SwiftPM package (`swift package init` or an existing `Package.swift`).
- Familiarity with Swift's `Codable` protocol. If you have used `JSONEncoder`, you already know the model.

## Step 1: Add the package dependency

Add swift-yaml to your `Package.swift` dependencies. Pin the current release — check the [releases page](https://github.com/21-DOT-DEV/swift-yaml/releases) for the latest tag.

```swift
dependencies: [
    .package(url: "https://github.com/21-DOT-DEV/swift-yaml.git", from: "1.0.0"),
],
```

## Step 2: Enable C++ interop on your target

Add the `YAML` product to your target **and** set `.interoperabilityMode(.Cxx)` in that target's `swiftSettings`. Both lines are required.

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "YAML", package: "swift-yaml"),
    ],
    swiftSettings: [
        .interoperabilityMode(.Cxx),
    ]
)
```

> Important: The `.interoperabilityMode(.Cxx)` setting is not optional, and it is viral: any target that imports `YAML` must set it, and so must any target that depends on *your* module if your public API exposes `YAML` types. Enabling C++ interop changes your module's ABI, so adding or removing it is a source-breaking, semver-major change. This is the deliberate cost of building on a C++-only upstream — see the [Swift and C++ interoperability guide](https://www.swift.org/documentation/cxx-interop/) for background.

You should now be able to `import YAML` and build with `swift build`.

## Step 3: Encode a value to YAML

Conform a type to `Codable` and hand an instance to ``YAMLEncoder/encode(_:)``. It returns the YAML document as a `String`.

```swift
import YAML

struct Server: Codable {
    var host: String
    var port: Int
    var tags: [String]
}

let server = Server(host: "localhost", port: 8080, tags: ["web", "staging"])
let yaml = try YAMLEncoder().encode(server)
print(yaml)
```

You should see block-style YAML with keys in declaration order and a two-space indent:

```yaml
host: localhost
port: 8080
tags:
  - web
  - staging
```

## Step 4: Decode it back

Pass the text and the target type to `decode(_:from:)` on ``YAMLDecoder``. Decoding is the mirror of encoding.

```swift
let restored = try YAMLDecoder().decode(Server.self, from: yaml)
// restored == server
```

``YAMLDecoder`` also reads a `[UInt8]` byte buffer (the Foundation-free path) and, where Foundation is available, a `Data` value — useful when the document arrives from a file handle or network socket.

> Note: A freshly created ``YAMLDecoder`` is already safe to point at untrusted input. Its ``YAMLDecoder/documentLimits`` reject malicious documents — alias bombs, runaway nesting, oversized payloads — before they can exhaust memory, with no configuration on your part. See <doc:SafeDecoding> for the threat model.

## What you just built

You wired swift-yaml into a package, enabled C++ interop, and used ``YAMLEncoder`` and ``YAMLDecoder`` to round-trip a `Codable` value with no hand-written mapping. From here, the library is configured the same way as Foundation's JSON codecs: set properties on the encoder or decoder to change behavior.

### Next steps

- <doc:Encoding> — shape the output: sorted keys, flow style, indentation, key and float strategies.
- <doc:Decoding> — decoding strategies, multiple input types, and error handling.
- <doc:SafeDecoding> — how the safe-by-default limits work and when to tune them.
- <doc:MigratingFromJSON> — coming from `JSONEncoder`/`JSONDecoder`.

<!-- last-reviewed: 2026-06-18 -->
