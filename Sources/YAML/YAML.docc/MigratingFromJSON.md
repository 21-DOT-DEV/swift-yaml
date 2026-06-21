# Migrating from JSONEncoder and JSONDecoder

@Metadata {
    @TitleHeading("How-To Guide")
}

Move existing `JSONEncoder`/`JSONDecoder` code to ``YAMLEncoder``/``YAMLDecoder``, with a map of the equivalent APIs and the handful of deliberate differences.

## Overview

swift-yaml is modeled on Foundation's JSON codecs on purpose, so most migrations are a type-name swap. ``YAMLEncoder`` and ``YAMLDecoder`` are `final class` configuration objects holding mutable strategy properties, exactly like [`JSONEncoder`](https://developer.apple.com/documentation/foundation/jsonencoder) and [`JSONDecoder`](https://developer.apple.com/documentation/foundation/jsondecoder), and they drive the same `Codable` machinery introduced in [SE-0167](https://github.com/apple/swift-evolution/blob/main/proposals/0167-swift-encoders.md). Your `Codable` types do not change at all.

This guide assumes swift-yaml is already added to your package, including the C++ interop setting that has no JSON analogue — if not, see <doc:GettingStarted> first.

## The API map

| Foundation | swift-yaml | Notes |
|---|---|---|
| `JSONEncoder()` | ``YAMLEncoder`` | ``YAMLEncoder/encode(_:)`` returns a `String`, not `Data` |
| `JSONDecoder()` | ``YAMLDecoder`` | safe-by-default ``YAMLDecoder/documentLimits`` |
| `.outputFormatting` | ``YAMLEncoder/outputFormatting`` | ``YAMLEncoder/OutputFormatting/sortedKeys`` is shared; ``YAMLEncoder/OutputFormatting/flowStyle`` is new |
| `.keyEncodingStrategy` | ``YAMLEncoder/keyEncodingStrategy`` | same cases |
| `.dateEncodingStrategy` | ``YAMLEncoder/dateEncodingStrategy`` | defaults to ``YAMLEncoder/DateEncodingStrategy/iso8601`` |
| `.dataEncodingStrategy` | ``YAMLEncoder/dataEncodingStrategy`` | same, defaults to ``YAMLEncoder/DataEncodingStrategy/base64`` |
| `.nonConformingFloatEncodingStrategy` | ``YAMLEncoder/nonConformingFloatEncodingStrategy`` | defaults to ``YAMLEncoder/NonConformingFloatEncodingStrategy/nativeYAML`` |
| `.userInfo` | ``YAMLEncoder/userInfo`` | same |
| (decoder strategies) | ``YAMLDecoder/keyDecodingStrategy`` etc. | same shapes |
| — | ``YAMLDecoder/duplicateKeyStrategy`` | YAML-specific |

The error model carries over too: both codecs throw the standard library's `EncodingError` and `DecodingError` with coding paths, so existing `catch` blocks keep working.

## What stays the same

Most code needs only the type name changed. The strategy enums share their names and cases, so a line like `decoder.keyDecodingStrategy = .convertFromSnakeCase` is identical on both sides.

```swift
// Before
let encoder = JSONEncoder()
encoder.keyEncodingStrategy = .convertToSnakeCase
encoder.outputFormatting = [.sortedKeys]
let data = try encoder.encode(value)

// After
let encoder = YAMLEncoder()
encoder.keyEncodingStrategy = .convertToSnakeCase
encoder.outputFormatting = [.sortedKeys]
let text = try encoder.encode(value)
```

## What is deliberately different

Five differences are intentional, reflecting YAML's nature rather than oversights.

**The encoder returns `String`.** ``YAMLEncoder/encode(_:)`` produces text, since YAML is a text format. Where you previously held `Data`, wrap the result: `Data(text.utf8)`.

**Non-finite floats don't throw.** `JSONEncoder` throws on infinity and NaN because JSON cannot represent them; YAML can, so ``YAMLEncoder`` emits `.inf`, `-.inf`, and `.nan` by default. Set ``YAMLEncoder/NonConformingFloatEncodingStrategy/throw`` to restore JSON's strict behavior.

**Dates default to ISO-8601.** `JSONEncoder` defaults to `.deferredToDate` (a raw reference-date `Double`); ``YAMLEncoder`` defaults to ``YAMLEncoder/DateEncodingStrategy/iso8601`` because a readable timestamp suits YAML's configuration-first use. Set the strategy explicitly if you need the numeric form.

**Decoding is bounded by default.** `JSONDecoder` enforces a fixed nesting limit; ``YAMLDecoder`` adds explicit, tunable budgets on depth, node count, and input size through ``YAMLDecoder/documentLimits``, because YAML's anchors and aliases open denial-of-service vectors JSON lacks. See <doc:SafeDecoding>.

**C++ interop is required.** Every target importing ``YAMLEncoder`` or ``YAMLDecoder`` must enable `.interoperabilityMode(.Cxx)`. There is no JSON equivalent — it is the cost of building on the yaml-cpp engine, covered in <doc:GettingStarted>.

## Verify the migration

Round-trip a representative value and confirm it survives. Because YAML decoding is an independent path from encoding, a clean round-trip exercises both directions.

```swift
let original = makeRepresentativeValue()
let text = try YAMLEncoder().encode(original)
let restored = try YAMLDecoder().decode(type(of: original), from: text)
assert(restored == original)
```

## Troubleshooting

**`encode(_:)` no longer returns `Data`.** That is expected — it returns `String`. Use `Data(text.utf8)` at the call site if a downstream API needs bytes.

**A value that used to throw on infinity now encodes as `.inf`.** ``YAMLEncoder`` defaults to native YAML tokens. Set ``YAMLEncoder/nonConformingFloatEncodingStrategy`` to ``YAMLEncoder/NonConformingFloatEncodingStrategy/throw`` to match `JSONEncoder`.

**Dates serialize differently than before.** The default changed to ``YAMLEncoder/DateEncodingStrategy/iso8601``. Pick ``YAMLEncoder/DateEncodingStrategy/secondsSince1970`` or ``YAMLEncoder/DateEncodingStrategy/deferredToDate`` to reproduce JSON's numeric output.

For the full encoding and decoding options, see <doc:Encoding> and <doc:Decoding>.

<!-- last-reviewed: 2026-06-18 -->
