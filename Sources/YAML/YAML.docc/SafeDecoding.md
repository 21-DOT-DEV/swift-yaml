# Parsing Untrusted YAML Safely

@Metadata {
    @TitleHeading("Explanation")
}

Why YAML is a denial-of-service vector, and how ``YAMLDecoder`` neutralizes the cheap attacks by default through ``YAMLDecoder/documentLimits``.

## Overview

YAML is more dangerous to parse than it looks. A few lines of input can instruct a naive parser to allocate gigabytes, recurse until the stack overflows, or simply hand it a payload too large to hold — all before your `Codable` types are ever consulted. swift-yaml treats decoding as a security boundary: ``YAMLDecoder`` bounds every parse with resource budgets that reject the known cheap attacks, and those budgets are **on by default**. This article explains what the attacks are, how the defense works, and when you might adjust it.

## The short answer

``YAMLDecoder`` enforces three limits on every document through ``YAMLDecoder/DocumentLimits`` — a cap on materialized nodes, a cap on nesting depth, and a cap on input size — and rejects anything over budget with a `DecodingError.dataCorrupted` wrapping ``YAMLError/documentTooComplex(_:)``. The defaults (depth 128, ten million nodes, 50 MiB) are generous enough that ordinary configuration and data-interchange documents never reach them, so the safety costs you nothing until an attacker shows up.

## The attacks

Three input-driven failure modes account for the cheap, high-impact attacks against a YAML reader.

### Alias-expansion bombs

The most famous is the "billion laughs" attack, adapted from XML to YAML's anchors and aliases. An [anchor](https://yaml.org/spec/1.2.2/) (`&name`) labels a node; an alias (`*name`) refers back to it. Nest aliases that each reference several copies of the previous layer, and the *logical* size of the document grows exponentially while the *text* stays tiny — a dozen lines can expand to billions of nodes. The class is catalogued as [CVE-2017-18640](https://nvd.nist.gov/vuln/detail/CVE-2017-18640) in SnakeYAML and has recurred across YAML libraries in every language.

The defense is ``YAMLDecoder/DocumentLimits/maxNodeCount``. The underlying [yaml-cpp](https://github.com/jbeder/yaml-cpp) loader keeps aliases *shared* in the parsed graph rather than expanding them, so the bomb only detonates when something walks the tree and materializes each reference. swift-yaml's tree walk is exactly that something — and it counts. Every node it materializes increments a budget, and the count trips long before memory is exhausted, because a bomb inflates the counter geometrically.

### Runaway nesting

A second attack skips aliases entirely: deeply nested collections — `[[[[…]]]]` in flow style, or thousands of leading spaces in block style — drive a recursive-descent parser to overflow its call stack inside the load itself, before any budget on the resulting tree can act.

The defense has two layers. ``YAMLDecoder/DocumentLimits/maxDepth`` caps nesting in the tree walk, and a cheap single-pass textual scan runs *before* the document reaches yaml-cpp, rejecting input whose flow brackets, compact block indicators, or indentation already exceed the depth limit. The scan is quote-aware, so brackets inside a string scalar don't count against you.

> Note: The default ``YAMLDecoder/DocumentLimits/maxDepth`` is **128**, well below `JSONDecoder`'s 512. This is a deliberate concession to the engine: yaml-cpp's flow parser was measured to hang on nesting past roughly 600 levels, and merely *accessing* a deeply nested node tree is super-linear, hanging by around 500. A limit of 128 sits safely below both cliffs while remaining far beyond any document a human or tool produces.

### Oversized payloads

The simplest attack is just a very large document — enough text to exhaust memory during parsing. ``YAMLDecoder/DocumentLimits/maxInputBytes`` caps the UTF-8 size (50 MiB by default) and is checked before parsing begins, so an oversized payload is rejected immediately rather than after allocation.

## Tuning the limits

Every limit lives on ``YAMLDecoder/documentLimits`` and is adjustable. Raise an individual budget when a legitimate document is genuinely large, or set a negative value to disable that one limit while keeping the others:

```swift
let decoder = YAMLDecoder()
decoder.documentLimits = YAMLDecoder.DocumentLimits(
    maxDepth: 256,            // raised from the default 128
    maxNodeCount: 50_000_000, // raised from the default 10_000_000
    maxInputBytes: -1         // disable the size cap only
)
```

For reference, the defaults are depth 128, 10,000,000 nodes, and 50 MiB; any parameter you don't pass keeps its default. For input you fully control and trust, ``YAMLDecoder/DocumentLimits/unbounded`` disables all three at once.

> Warning: ``YAMLDecoder/DocumentLimits/unbounded`` removes every guard. Use it only for input from a trusted source — a file you generated, a resource you bundle — never for data that crosses a trust boundary such as a network request or user upload.

## Limitations

The protection is real but bounded, and it is worth naming what it does and doesn't promise:

- **The budgets are heuristic, not a proof.** The defaults are tuned to yaml-cpp's measured cliffs, not derived from a formal model. They defend the known cheap attacks; they are not a guarantee against every conceivable pathological input.
- **Strict duplicate-key rejection is opt-in.** Set ``YAMLDecoder/duplicateKeyStrategy`` to ``YAMLDecoder/DuplicateKeyStrategy/reject`` and decoding throws on the first repeated mapping key (an event-driven scan of the first document, run after the size/depth budgets). It is off by default — enable it where a doubled key would be a data-integrity hazard. See <doc:Decoding>.
- **Resource limits are not semantic validation.** These budgets bound CPU and memory; they do not vet meaning. A small, well-formed document can still carry values that are dangerous to *your* application — that validation remains yours to perform.
- **`.unbounded` is a foot-gun by design.** It exists for trusted input and turns off everything above. Reach for raising an individual limit before disabling the lot.

## Related reading

- [CVE-2017-18640](https://nvd.nist.gov/vuln/detail/CVE-2017-18640) — the SnakeYAML alias-expansion advisory that typifies the billion-laughs class.
- [YAML 1.2 specification](https://yaml.org/spec/1.2.2/) — anchors, aliases, and the core schema.
- <doc:Decoding> — the decoding workflow these limits protect.

<!-- last-reviewed: 2026-06-18 -->
