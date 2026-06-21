# ``YAML``

Encode and decode Swift `Codable` types to and from YAML 1.2, with the ergonomics of `JSONEncoder`/`JSONDecoder` and safe-by-default parsing of untrusted input.

## Overview

`YAML` is an idiomatic YAML codec for Swift, built on the vendored [yaml-cpp](https://github.com/jbeder/yaml-cpp) 0.6.2 engine. It mirrors Foundation's `JSONEncoder` and `JSONDecoder` closely enough that adoption is mostly swapping the type name: any `Encodable` or `Decodable` value round-trips through ``YAMLEncoder`` and ``YAMLDecoder`` with no bespoke mapping.

```swift
import YAML

struct Server: Codable { var host: String; var port: Int }

let text = try YAMLEncoder().encode(Server(host: "localhost", port: 8080))
// host: localhost
// port: 8080

let server = try YAMLDecoder().decode(Server.self, from: text)
```

Three properties shape the design.

**Codable-native.** ``YAMLEncoder`` and ``YAMLDecoder`` drive the standard library's `Encoder` and `Decoder` machinery directly, so nested structures, arrays, dictionaries, enums with associated values, and custom `CodingKeys` all work without hand-written mapping — exactly as they do with JSON. The encoder returns a `String`; the decoder reads a `String`, a `[UInt8]`, or (with Foundation) a `Data`.

**Safe by default.** ``YAMLDecoder`` bounds untrusted input through ``YAMLDecoder/documentLimits``, rejecting alias-expansion "billion laughs" bombs, pathologically deep nesting, and oversized payloads before they exhaust memory or overflow the parser stack — with zero configuration. The defaults are generous enough that ordinary documents never trip them; opt out with ``YAMLDecoder/DocumentLimits/unbounded`` only for fully trusted input.

**Foundation-light and portable.** The codec core is Foundation-free. The `Date` and `Data` conveniences are gated behind FoundationEssentials or Foundation and compile away where neither is present, so behavior is identical on Linux and server deployments as on Apple platforms.

> Important: The `YAML` module is built on Swift's C++ interoperability, so **every target that imports it must enable C++ interop** by adding `.interoperabilityMode(.Cxx)` to that target's `swiftSettings`. This requirement is viral — it propagates to every downstream dependent — and toggling it is a source-breaking, semver-major change. See <doc:GettingStarted> for the exact `Package.swift` configuration.

New to the library? Start with <doc:GettingStarted>. Coming from Foundation's JSON codecs? <doc:MigratingFromJSON> maps the differences and the deliberate departures.

## Topics

### Essentials

- <doc:GettingStarted>
- ``YAMLEncoder``
- ``YAMLDecoder``

### Guides

- <doc:Encoding>
- <doc:Decoding>
- <doc:SafeDecoding>
- <doc:MigratingFromJSON>

### Encoding Configuration

- ``YAMLEncoder/OutputFormatting``
- ``YAMLEncoder/KeyEncodingStrategy``
- ``YAMLEncoder/NonConformingFloatEncodingStrategy``
- ``YAMLEncoder/DateEncodingStrategy``
- ``YAMLEncoder/DataEncodingStrategy``

### Decoding Configuration

- ``YAMLDecoder/KeyDecodingStrategy``
- ``YAMLDecoder/NonConformingFloatDecodingStrategy``
- ``YAMLDecoder/DuplicateKeyStrategy``
- ``YAMLDecoder/DateDecodingStrategy``
- ``YAMLDecoder/DataDecodingStrategy``

### Safe Decoding

- ``YAMLDecoder/DocumentLimits``

### Errors

- ``YAMLError``

<!-- last-reviewed: 2026-06-18 -->
