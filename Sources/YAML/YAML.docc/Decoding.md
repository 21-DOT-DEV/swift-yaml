# Decoding YAML Into Your Types

@Metadata {
    @TitleHeading("How-To Guide")
}

Decode YAML into `Codable` types from a string, bytes, or `Data`, configure how keys and scalars are interpreted, and handle malformed input.

## Overview

``YAMLDecoder`` reads a YAML document into any `Decodable` type using the standard library's decoding machinery, so the model matches Foundation's [`JSONDecoder`](https://developer.apple.com/documentation/foundation/jsondecoder). The wrinkle YAML adds is that scalars are untyped text — `42`, `true`, and `null` are all just strings until something asks for a concrete type — so ``YAMLDecoder`` resolves each scalar to the Swift type your `Codable` declarations request.

This guide assumes you can already decode a basic value; if not, begin with <doc:GettingStarted>.

## Decode from a string, bytes, or data

The primary method on ``YAMLDecoder``, `decode(_:from:)`, reads a `String`. Two more overloads cover the common byte sources: a `[UInt8]` buffer (the Foundation-free entry point) and, where Foundation is present, a `Data`. All three share the same configuration and error behavior.

```swift
let decoder = YAMLDecoder()

let a = try decoder.decode(Server.self, from: "host: localhost\nport: 8080")
let b = try decoder.decode(Server.self, from: Array("host: localhost\nport: 8080".utf8))
let c = try decoder.decode(Server.self, from: someData)   // Foundation only
```

## Match snake_case keys

Set ``YAMLDecoder/keyDecodingStrategy`` to ``YAMLDecoder/KeyDecodingStrategy/convertFromSnakeCase`` when the document uses `snake_case` but your properties are `camelCase`. It is the exact inverse of the encoder's conversion: `max_retry_count` resolves to `maxRetryCount`, and leading or trailing underscores are preserved.

```swift
let decoder = YAMLDecoder()
decoder.keyDecodingStrategy = .convertFromSnakeCase
let config = try decoder.decode(Config.self, from: "max_retry_count: 3")
```

For mappings that don't follow the snake/camel convention, ``YAMLDecoder/KeyDecodingStrategy/custom(_:)`` gives you the coding path and lets you return the key to look up.

## Resolve floats, dates, and data

Non-finite floats decode from YAML's native tokens by default. ``YAMLDecoder/nonConformingFloatDecodingStrategy`` starts at ``YAMLDecoder/NonConformingFloatDecodingStrategy/nativeYAML``, which recognizes `.inf`, `-.inf`, and `.nan` (in the capitalizations the [YAML 1.2 core schema](https://yaml.org/spec/1.2.2/) allows). Use ``YAMLDecoder/NonConformingFloatDecodingStrategy/convertFromString(positiveInfinity:negativeInfinity:nan:)`` to read sentinel strings instead.

With Foundation available, ``YAMLDecoder/dateDecodingStrategy`` defaults to ``YAMLDecoder/DateDecodingStrategy/iso8601``. The parser accepts a `T` or space separator, an optional fractional second, and a `Z` or `±HH:MM` zone offset — the [RFC 3339](https://datatracker.ietf.org/doc/html/rfc3339) profile — and throws if the string isn't a valid date. ``YAMLDecoder/dataDecodingStrategy`` defaults to ``YAMLDecoder/DataDecodingStrategy/base64``.

## Decide how duplicate keys resolve

``YAMLDecoder/duplicateKeyStrategy`` decides what happens when a key repeats, defaulting to ``YAMLDecoder/DuplicateKeyStrategy/useLast``.

> Note: yaml-cpp exposes both entries of a repeated key, so the overlay applies the setting while building the value — ``YAMLDecoder/DuplicateKeyStrategy/useFirst`` keeps the first value, ``YAMLDecoder/DuplicateKeyStrategy/useLast`` (the default) the last. ``YAMLDecoder/DuplicateKeyStrategy/reject`` refuses the document instead, throwing a ``YAMLError/duplicateKey(key:line:column:)`` (wrapped as `DecodingError.dataCorrupted`) at the first repeated **scalar** key in the first document. (Null, alias, and whole-structure keys are consumed for parity but not compared.)

## Handle malformed and oversized input

``YAMLDecoder`` throws the standard library's `DecodingError` for ordinary failures — a type mismatch, a missing key, a wrong shape. Two YAML-specific situations (a syntax error, or input that trips a safety budget) surface as `DecodingError.dataCorrupted` carrying a ``YAMLError`` in its `underlyingError`, so you can catch the familiar type and still recover structured detail.

```swift
do {
    let config = try YAMLDecoder().decode(Config.self, from: untrustedText)
} catch let DecodingError.dataCorrupted(context) {
    if let yamlError = context.underlyingError as? YAMLError {
        switch yamlError {
        case let .parse(message, line, column):
            print("Syntax error at \(line):\(column) — \(message)")
        case let .documentTooComplex(detail):
            print("Rejected by a safety limit: \(detail)")
        case let .duplicateKey(key, line, column):
            print("Duplicate key '\(key)' at \(line):\(column)")   // under .reject
        case .emit:
            break   // encode-only
        @unknown default:
            break   // YAMLError is non-frozen — handle cases added in future versions
        }
    }
} catch {
    print("Shape mismatch: \(error)")
}
```

``YAMLError`` is not frozen, so a future release may add cases; the `@unknown default:` keeps an exhaustive `switch` over it source-compatible when that happens (see Swift Evolution [SE-0192](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0192-non-exhaustive-enums.md)).

The ``YAMLError/parse(message:line:column:)`` case reports a 1-based line and column (the overlay adds 1 to yaml-cpp's 0-based marks), which is usually enough to point a user at the offending line.

> Warning: The safety limits in ``YAMLDecoder/documentLimits`` are on by default and surface as ``YAMLError/documentTooComplex(_:)``. Do not disable them for input you don't fully control — see <doc:SafeDecoding>.

## Troubleshooting

**Decoding threw `dataCorrupted` with a ``YAMLError`` inside.** The input is either malformed (``YAMLError/parse(message:line:column:)`` gives the position) or exceeded a budget (``YAMLError/documentTooComplex(_:)``). Inspect `context.underlyingError` as shown above.

**A `snake_case` document failed with "key not found".** Set ``YAMLDecoder/keyDecodingStrategy`` to ``YAMLDecoder/KeyDecodingStrategy/convertFromSnakeCase``, or align your `CodingKeys`.

**A quoted number or boolean decoded as a `String`.** That is correct: `"123"` in quotes is a string scalar, and decoding it into an `Int` will throw a type mismatch. Remove the quotes in the source for a numeric type.

For the encoding side of these strategies, see <doc:Encoding>.

<!-- last-reviewed: 2026-06-18 -->
