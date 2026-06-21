# Controlling Encoded Output

@Metadata {
    @TitleHeading("How-To Guide")
}

Shape the YAML that ``YAMLEncoder`` produces — indentation, key order, flow vs. block style, and how keys, floats, dates, and data are formatted.

## Overview

``YAMLEncoder`` produces readable block-style YAML out of the box, but you often need a specific shape: sorted keys for a stable diff, `snake_case` keys for an external schema, compact flow style for a one-line value. You get there by setting properties on the encoder before calling ``YAMLEncoder/encode(_:)`` — the same configuration model as Foundation's [`JSONEncoder`](https://developer.apple.com/documentation/foundation/jsonencoder), whose strategy set this API deliberately mirrors ([SE-0167](https://github.com/apple/swift-evolution/blob/main/proposals/0167-swift-encoders.md)).

This guide assumes you can already encode a value — if not, start with <doc:GettingStarted>.

## Set indentation and key order

Use ``YAMLEncoder/indent`` for nesting width and ``YAMLEncoder/outputFormatting`` for document-level toggles. ``YAMLEncoder/OutputFormatting/sortedKeys`` orders mapping keys lexicographically instead of preserving the order your `CodingKeys` declare.

```swift
let encoder = YAMLEncoder()
encoder.indent = 4
encoder.outputFormatting = [.sortedKeys]

let yaml = try encoder.encode(Server(host: "localhost", port: 8080))
// port: 8080
// host: localhost   ← sorted: "host" < "port", emitted host-first
```

Sorted keys make output deterministic, which matters for snapshot tests and version-controlled config.

## Emit compact flow style

Add ``YAMLEncoder/OutputFormatting/flowStyle`` to emit inline `{key: value}` mappings and `[a, b]` sequences instead of multi-line block style.

```swift
let encoder = YAMLEncoder()
encoder.outputFormatting = [.flowStyle]

let yaml = try encoder.encode(Server(host: "localhost", port: 8080, tags: ["web"]))
// {host: localhost, port: 8080, tags: [web]}
```

Flow style suits small values embedded in a larger document or log line; block style stays more readable as documents grow.

## Convert keys to snake_case

Set ``YAMLEncoder/keyEncodingStrategy`` to ``YAMLEncoder/KeyEncodingStrategy/convertToSnakeCase`` to translate your `camelCase` property names on the way out. Acronyms are handled at their boundary, so `myURLValue` becomes `my_url_value`.

```swift
struct Config: Codable { var maxRetryCount: Int; var enableTLS: Bool }

let encoder = YAMLEncoder()
encoder.keyEncodingStrategy = .convertToSnakeCase
let yaml = try encoder.encode(Config(maxRetryCount: 3, enableTLS: true))
// max_retry_count: 3
// enable_tls: true
```

For a mapping that doesn't fit the camel/snake model, ``YAMLEncoder/KeyEncodingStrategy/custom(_:)`` hands you the coding path and lets you return any key.

## Choose how non-finite floats are written

By default ``YAMLEncoder`` emits infinity and NaN using YAML's native `.inf`, `-.inf`, and `.nan` tokens — the ``YAMLEncoder/NonConformingFloatEncodingStrategy/nativeYAML`` case. This is the most visible departure from `JSONEncoder`, which throws on these values because JSON has no syntax for them.

```swift
let yaml = try YAMLEncoder().encode(["ratio": Double.infinity])
// ratio: .inf
```

If you need JSON-compatible strictness, switch to ``YAMLEncoder/NonConformingFloatEncodingStrategy/throw`` (raises `EncodingError`) or ``YAMLEncoder/NonConformingFloatEncodingStrategy/convertToString(positiveInfinity:negativeInfinity:nan:)`` to emit sentinel strings of your choosing.

## Format dates and data

With Foundation available, ``YAMLEncoder/dateEncodingStrategy`` defaults to ``YAMLEncoder/DateEncodingStrategy/iso8601`` — a UTC timestamp such as `2026-06-18T12:00:00Z`, which profiles the [RFC 3339](https://datatracker.ietf.org/doc/html/rfc3339) date-time format and reads far more naturally in YAML than a raw reference-date number. ``YAMLEncoder/DateEncodingStrategy/secondsSince1970`` and ``YAMLEncoder/DateEncodingStrategy/millisecondsSince1970`` emit numeric epochs instead.

``YAMLEncoder/dataEncodingStrategy`` defaults to ``YAMLEncoder/DataEncodingStrategy/base64`` ([RFC 4648](https://datatracker.ietf.org/doc/html/rfc4648)); use ``YAMLEncoder/DataEncodingStrategy/deferredToData`` to defer to `Data`'s own `Encodable` conformance, which emits a YAML sequence of byte values instead.

> Note: The `Date` and `Data` strategies exist only where FoundationEssentials or Foundation is importable. On a Foundation-free build they compile away, and the rest of the encoder still works.

## Verify it worked

The strongest check is a round-trip: decode the output back and compare. Because parsing runs through a different code path than emission, a successful round-trip exercises both.

```swift
let original = Server(host: "localhost", port: 8080)
let yaml = try YAMLEncoder().encode(original)
let restored = try YAMLDecoder().decode(Server.self, from: yaml)
assert(restored == original)
```

## Troubleshooting

**A string value came out double-quoted.** The encoder quotes any string scalar that would otherwise be re-read as a different type — `"true"`, `"123"`, `"null"`, `".inf"` — or that has significant leading or trailing whitespace. The quotes are intentional: they guarantee the value decodes back as a `String` rather than a `Bool`, `Int`, or null.

**Keys are in an order I didn't expect.** Without ``YAMLEncoder/OutputFormatting/sortedKeys``, keys follow your type's `CodingKeys` declaration order, not alphabetical order. Add `.sortedKeys` for a stable lexicographic layout.

**Encoding a non-finite `Double` threw.** You have ``YAMLEncoder/NonConformingFloatEncodingStrategy/throw`` selected (or are encoding through a path expecting JSON semantics). Switch to ``YAMLEncoder/NonConformingFloatEncodingStrategy/nativeYAML`` to emit `.inf`/`.nan`.

For the decoding side of every strategy here, see <doc:Decoding>.

<!-- last-reviewed: 2026-06-18 -->
