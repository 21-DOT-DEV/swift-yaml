# YAML API Proposal

`YAMLEncoder` / `YAMLDecoder` with full `Codable` support over the existing
`yamlcpp` (yaml-cpp 0.6.2) wrap, so consumers write `import YAML`.

Status: **APPROVED** (2026-06-16, defaults accepted: dup-key `.useLast` with
strict `.throw` deferred; date `.iso8601`; `@available`-gated date strategy;
top-level `encode` returns `String`; multi-doc + public `YAMLValue` deferred).
Building Phases 3–4.

---

## 1. Shape & precedent

- **Shape category:** codec (Encoder/Decoder + `Codable`).
- **Models:** Foundation's `JSONEncoder` / `JSONDecoder` for the *mechanics*
  (top-level config classes + an internal `Encoder`/`Decoder` with the three
  container kinds); **Yams** for the *YAML-specific choices* (returns
  `String`, native `.inf`/`.nan`, scalar-type resolution at decode time) so
  existing Swift YAML users meet a familiar surface.
- **Conventions borrowed:**
  - Top-level `final class` encoder/decoder holding mutable options + `userInfo`.
  - Strategy enums: key, date, data, non-conforming-float — same names/shapes
    as `JSONEncoder` where they apply.
  - `Encoder`/`Decoder` protocol conformance via keyed / unkeyed /
    single-value containers, so *any* `Codable` type works (not a hand-mapped
    subset).
  - Standard-library `EncodingError` / `DecodingError` with coding paths;
    parser failures surfaced as `DecodingError.dataCorrupted` carrying
    line:column.

## 2. Public surface & capability coverage

### Capability survey (yaml-cpp 0.6.2, cheaply reachable = already in vendored headers)

| Capability | Verdict | Notes |
|---|---|---|
| Parse text → node tree (`YAML::Load`) | **expose now** | decode path |
| Emit node/events → text (`YAML::Emitter`, indent, flow/block) | **expose now** | encode path + `outputFormatting` |
| Scalar type resolution (int/double/bool/null) | **expose now** | done in Swift per requested type (faithful YAML model) |
| Sorted keys / indent width / flow style | **expose now** | YAML analogue of `JSONEncoder.outputFormatting` |
| Native `.inf` / `.nan` | **expose now** | YAML has these; nicer than JSON's throw-by-default |
| Anchors/aliases expansion | **bounded** | accepted on input under a node/depth budget (safety §4); not emitted |
| Multi-document streams (`LoadAll`) | **defer** | second API tier (`decodeAll`); v1 is single-document |
| A public `YAMLValue` node type | **defer** | internal in v1; promote later if requested |
| Comment preservation / round-trip | **out-of-scope** | infeasible on 0.6.2's engine; documented |
| Strict duplicate-key rejection | **defer (documented)** | `YAML::Load` collapses dup keys (last-wins) before we see the tree; strict mode needs a custom event handler — see §4 + §6 |

### Encoder

```swift
public final class YAMLEncoder {
    public init()

    public var outputFormatting: OutputFormatting = []
    public var indent: Int = 2
    public var keyEncodingStrategy: KeyEncodingStrategy = .useDefaultKeys
    public var nonConformingFloatEncodingStrategy: NonConformingFloatEncodingStrategy = .nativeYAML
    public var dateEncodingStrategy: DateEncodingStrategy = .iso8601          // Foundation-gated
    public var dataEncodingStrategy: DataEncodingStrategy = .base64           // Foundation-gated
    public var userInfo: [CodingUserInfoKey: any Sendable] = [:]

    public func encode<T: Encodable>(_ value: T) throws -> String            // single top-level method

    public struct OutputFormatting: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int)
        public static let sortedKeys: OutputFormatting   // sort mapping keys
        public static let flowStyle:  OutputFormatting   // compact { } / [ ] inline style
    }
    public enum KeyEncodingStrategy: Sendable {
        case useDefaultKeys
        case convertToSnakeCase
        case custom(@Sendable ([any CodingKey]) -> any CodingKey)
    }
    public enum NonConformingFloatEncodingStrategy: Sendable {
        case nativeYAML                                                       // .inf / -.inf / .nan
        case `throw`
        case convertToString(positiveInfinity: String, negativeInfinity: String, nan: String)
    }
    // DateEncodingStrategy / DataEncodingStrategy: mirror JSONEncoder, Foundation-gated (§3).
}
```

### Decoder

```swift
public final class YAMLDecoder {
    public init()

    public var keyDecodingStrategy: KeyDecodingStrategy = .useDefaultKeys
    public var nonConformingFloatDecodingStrategy: NonConformingFloatDecodingStrategy = .nativeYAML
    public var dateDecodingStrategy: DateDecodingStrategy = .iso8601          // Foundation-gated
    public var dataDecodingStrategy: DataDecodingStrategy = .base64           // Foundation-gated
    public var duplicateKeyStrategy: DuplicateKeyStrategy = .useLast          // see §4/§6
    public var documentLimits: DocumentLimits = .default                      // safety budget (§4)
    public var userInfo: [CodingUserInfoKey: any Sendable] = [:]

    public func decode<T: Decodable>(_ type: T.Type, from yaml: String) throws -> T
    public func decode<T: Decodable>(_ type: T.Type, from data: [UInt8]) throws -> T   // Foundation-free
    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T      // Foundation-gated

    public enum KeyDecodingStrategy: Sendable {
        case useDefaultKeys
        case convertFromSnakeCase
        case custom(@Sendable ([any CodingKey]) -> any CodingKey)
    }
    public enum NonConformingFloatDecodingStrategy: Sendable {
        case nativeYAML
        case `throw`
        case convertFromString(positiveInfinity: String, negativeInfinity: String, nan: String)
    }
    public enum DuplicateKeyStrategy: Sendable { case useFirst, useLast }     // .throw deferred (§6)

    public struct DocumentLimits: Sendable {
        public var maxDepth: Int          // default 512
        public var maxNodeCount: Int      // default 10_000_000
        public var maxInputBytes: Int     // default 50 * 1024 * 1024
        public static let `default`: DocumentLimits
        public static let unbounded: DocumentLimits   // opt out (trusted input)
    }
}
```

### Error model

- Standard-library `EncodingError` / `DecodingError` (these are **stdlib, not
  Foundation**) thrown from the containers — matching `JSONEncoder`/`Decoder`.
- A small public `YAMLError` for the genuinely YAML-specific failures, also
  attached as the `underlyingError` of `DecodingError.dataCorrupted` so the
  familiar type is what callers catch:

```swift
public enum YAMLError: Error, CustomStringConvertible, Sendable {
    case parse(message: String, line: Int, column: Int)   // yaml-cpp ParserException
    case documentTooComplex(String)                       // safety budget exceeded
    case emit(String)                                     // emitter failure
    public var description: String { get }
}
```

## 3. Path & dependency

- **Path B** (Phase-0 classification: C++-only module + `*Shims`). The product
  builds **on `yamlcppShims`** with `.interoperabilityMode(.Cxx)`, reusing and
  extending the `yamlx::` helpers exactly as the wrap's smoke test already
  drives them. **No `CYAML`, no `extern "C"` bridge.**
- **Consumer import line:** `import YAML` — and consumers must enable
  `.interoperabilityMode(.Cxx)` on their target. This is **viral and
  semver-major**: the accepted cost of a C++-only upstream, stated plainly.
- **New product:** `.library(name: "YAML", targets: ["YAML"])` beside the
  existing `yamlcpp` library.
- **Module-name note:** the Swift module `YAML` collides with yaml-cpp's C++
  `YAML` namespace as imported into Swift. The overlay therefore reaches the
  native surface **exclusively through the `yamlx::` shim namespace** (incl. a
  `yamlx::Node` / `yamlx::Emitter` typedef and `void*` emitter handle) and
  never writes a bare `YAML.Load` in Swift — sidestepping the ambiguity.
- **Foundation posture:** **Foundation-free core** (the `Encoder`/`Decoder`,
  the three containers, `CodingKey`, `Encoding/DecodingError`, scalar handling
  are all stdlib). `Date`/`Data` conveniences are gated:
  ```swift
  #if canImport(FoundationEssentials)
  import FoundationEssentials
  #elseif canImport(Foundation)
  import Foundation
  #endif
  ```
  Date strategies use `Date.ISO8601FormatStyle` (Essentials-safe), `@available`-gated
  so the package needs **no** package-wide platform floor (open question §6).
  `decode(from: [UInt8])` is the Foundation-free entry point; the `Data`
  overload and date/data strategies compile away on platforms without
  Foundation. So `import YAML` carries no Foundation cost on Linux (Yams#358).

### Helpers to ADD to `yamlcpp_shims.h` (value-returning, non-template, `yamlx::` style)

All are exception-guarded (`try { … } catch (...)`) — a C++ exception crossing
into Swift interop is UB (the documented ~35-min hang). Failure crosses as a
*value*; Swift turns it into a typed `throw`.

```cpp
namespace yamlx {
  using Node = YAML::Node;                 // avoid bare YAML.* in Swift

  // --- decode boundary ---
  struct ParseResult { bool ok; Node root; long line; long column; std::string message; };
  ParseResult parse(const char* input);            // wraps YAML::Load, catches ParserException
  int         nodeKind(const Node&);               // 0 undef / 1 null / 2 scalar / 3 seq / 4 map
  long        count(const Node&);                  // size(), guarded
  std::string scalarText(const Node&);             // Scalar() ref → value copy, guarded
  std::string nodeTag(const Node&);                // Tag()
  Node        seqItem(const Node&, long i);        // operator[]<size_t>, guarded
  std::string mapKeyText(const Node&, long i);     // i-th key's scalar text (iterator advance)
  Node        mapValue(const Node&, long i);       // i-th value (iterator advance)

  // --- encode boundary (event-streamed Emitter; scalar quoting is controllable
  //     only via the manipulator, not EmitterStyle) ---
  void*       newEmitter();                         // returns YAML::Emitter* as opaque handle
  void        freeEmitter(void*);
  void        emitterSetIndent(void*, long n);
  bool        emitterOK(void*);
  std::string emitterError(void*);
  std::string emitterText(void*);                  // c_str() → value copy
  void        beginMap(void*, bool flow);  void endMap(void*);
  void        beginSeq(void*, bool flow);  void endSeq(void*);
  void        emitKeyToken(void*);         void emitValueToken(void*);
  void        emitNull(void*);                     // ~
  void        emitPlainScalar(void*, const char*);  // numbers/bools (already formatted in Swift)
  void        emitQuotedScalar(void*, const char*); // strings needing type-preservation
}
```

(The existing `at`/`atIndex`/`asInt`/`asString` stay for the smoke test; the
overlay does **not** rely on the throwing `asInt`/`asString` — it uses the
guarded `scalarText` + Swift-side parsing instead, per the "audit inherited
helpers" rule.)

## 4. Safety posture

The overlay is the safety layer; yaml-cpp is unsafe-by-default. Hardened in
authored Swift/shims, **no wrap edits**:

| Footgun (input-driven) | Real-world | Safe default |
|---|---|---|
| **Alias-expansion "billion laughs" bomb** — `&a [*b,*b,…]` nests to exponential size on materialization | CVE class: SnakeYAML CVE-2017-18640, hit Kubernetes | tree-walk enforces `maxNodeCount` + `maxDepth`; throws `DecodingError.dataCorrupted` (`YAMLError.documentTooComplex`) before blow-up. `Load` itself keeps aliases *shared* (no expansion), so the budget on our walk is the real guard. |
| **Deep nesting** `[[[[…]]]]` overflowing yaml-cpp's recursive-descent parser stack *inside `Load`* | parser DoS | cheap pre-parse textual nesting scan rejects input deeper than `maxDepth` **before** `Load` is called; plus `maxDepth` in the walk |
| **Oversized payload** | memory DoS | `maxInputBytes` checked before parse |
| **Duplicate mapping keys** silently last-wins | data-integrity / request smuggling | `duplicateKeyStrategy` (default `.useLast`, matching yaml-cpp). Strict `.throw` deferred — see §6 (honest: `Load` collapses dups before the overlay sees them). |

All limits live on `YAMLDecoder.documentLimits`, default-on, opt-out via
`.unbounded` for trusted input. The defaults are generous enough that ordinary
config/documents never trip them.

## 5. Test plan

- **Oracle (independent, not just round-trip):**
  1. `Codable` round-trip on authored types (nested structs/enums/optionals/
     arrays/dictionaries, `CodingKeys`, `super`encoders).
  2. **Re-parse our `YAMLEncoder` output through yaml-cpp** (`yamlx::parse`, a
     *different* code path than our event-stream emit) and compare structure.
  3. **Cross-check against `JSONDecoder`/`JSONEncoder`** on the shared
     JSON-compatible data model (same struct decodes to equal values from YAML
     and JSON) — a reference that does not share our implementation.
- **Authoritative inputs:** YAML spec examples already cited in the wrap's
  smoke test (`test/specexamples.h` 2.1/2.2) + authored `Codable` fixtures
  derived from the spec, never from our own output.
- **Safety tests (prove each declared default):**
  - a ~10-line alias bomb is rejected within the budget — no OOM/hang;
  - an over-deep document is rejected by the pre-parse guard — no crash;
  - an oversized input is rejected;
  - malformed YAML throws `DecodingError.dataCorrupted` with a useful
    line:column, not a trap.
- **Structural:** test target enables `.interoperabilityMode(.Cxx)` (mirrors
  the smoke test); a proposal-conformance check instantiates every public
  entry point.

## 6. Open questions (defaults chosen if you don't object)

1. **Strict duplicate-key rejection.** `YAML::Load` collapses duplicates
   (last-wins) before the overlay can see them, so true `.throw` needs a
   custom yaml-cpp `EventHandler` parse path. **Default: ship `.useLast`/
   `.useFirst` in v1, defer strict `.throw` (documented).** Want me to build
   the event-handler path now instead? (bigger shim, but full strict mode)
2. **Date default.** `JSONEncoder` defaults to `.deferredToDate` (raw Double).
   YAML reads nicer with ISO-8601. **Default: `.iso8601`** (and offer the
   full strategy set). OK to deviate from JSONEncoder here?
3. **Platform floor vs `@available`.** `Date.ISO8601FormatStyle` needs
   macOS 12 / iOS 15+. **Default: `@available`-gate the iso8601 strategy** so
   the package keeps no platform floor (Linux/older Apple still build the
   Foundation-free core). Prefer a package-wide `platforms:` floor instead?
4. **`Data` output from the encoder.** Top-level `encode` returns `String`
   only (avoids the return-type-overload ambiguity trap). `Data(yaml.utf8)` is
   trivial for callers. **Default: String only.** Add a `[UInt8]` convenience?
5. **Multi-document** (`LoadAll`) and a **public `YAMLValue`** node API are
   **deferred** to a second tier. Pull either into v1?

---

*On approval I proceed to Phase 3 (extend `yamlcppShims`, build `Sources/YAML`)
then Phase 4 (verify). DocC and examples are out of scope for this skill and
will be offered as a handoff.*

---

## Done report (2026-06-16)

**Added**
- Product target `Sources/YAML` (11 files: `YAMLEncoder`/`YAMLDecoder`, the
  two-tier internal `_YAMLEncoder`/`_YAMLDecoder` + all three container kinds
  each side, `YAMLValue` model, scalar/key/ISO-8601 helpers, `YAMLError`, the
  `YAMLSerialization` C++ boundary), with `.interoperabilityMode(.Cxx)`.
- New `.library(name: "YAML", targets: ["YAML"])`.
- Test target `Tests/YAMLTests` (6 suites, 43 tests with the wrap's own smoke
  suite).
- Helpers added to `yamlcppShims` (all exception-guarded, value-returning):
  `parse` (+ `ParseResult`), `nodeKind`, `count`, `scalarText`, `nodeTag`,
  `seqItem`, `mapKeyText`, `mapValue`, and the event-streamed emitter set
  (`newEmitter`/`freeEmitter`/`emitterSetIndent`/`emitterOK`/`emitterError`/
  `emitterText`/`beginMap`/`endMap`/`beginSeq`/`endSeq`/`emitKeyToken`/
  `emitValueToken`/`emitNull`/`emitPlainScalar`/`emitQuotedScalar`), plus a
  `yamlx::Node` alias. The original `at`/`atIndex`/`asInt`/`asString` are
  untouched (still used by the wrap's smoke test).

**Consumer import line** — `import YAML`. The product rides the C++-interop
shims, so **every consuming target must set `.interoperabilityMode(.Cxx)`**
(viral, semver-major — the accepted cost of a C++-only upstream).

**Path taken** — B (build on `yamlcppShims` + `.Cxx`). No `extern "C"` bridge;
the overlay reuses/extends the `yamlx::` helpers exactly as the smoke test does.
The product module is named `YAML`; to avoid colliding with yaml-cpp's C++
`YAML` namespace it reaches the native surface only through `yamlx::`.

**Verification** — `swift build` and `swift test` both green: **43 tests, 0
failures**. Oracle = Codable round-trips **+** re-parsing our emitter output
through yaml-cpp (independent code path) **+** agreement with Foundation's
`JSONDecoder`/`JSONEncoder` on the shared model. Safety proven: alias bomb and
deep nesting rejected (no hang/OOM), oversized input rejected, malformed input
throws `DecodingError.dataCorrupted` with line/column.

**Deviations from the proposal (empirically driven, all in the safety budget)**
- **Default `maxDepth` 512 → 128.** During Phase 4 yaml-cpp was measured to
  hang on flow nesting past ~600 deep, and *accessing* a deeply nested node
  tree is super-linear (hangs by ~500). 128 sits far below both cliffs and
  beyond any real document. (`JSONDecoder` uses 512; yaml-cpp can't match it.)
- **Nesting guard widened.** The pre-parse guard now bounds flow brackets **and**
  compact block (`- - - -`) **and** indentation depth, not flow alone — deep
  *block* documents would otherwise choke yaml-cpp's `Load` before the node
  budget could act.
- All safety limits now uniformly surface as `DecodingError.dataCorrupted`
  wrapping `YAMLError` (the input-size check previously threw `YAMLError` raw).

**Deferred** (unchanged from the proposal)
- DocC catalog/articles and `///` doc comments → the docc suite (`docc-symbols`
  / `docc-articles` / `docc-audit`). Offered as a handoff.
- Strict duplicate-key `.throw`; multi-document `LoadAll`; a public `YAMLValue`
  node API; `[UInt8]`/`Data` output from the encoder.
- No demo app / `Examples/` — the test target is the consumer demo.

**Residual safety note** — extreme *indentation*-based nesting via crafted
multi-KB input is bounded by the new indentation guard + `maxInputBytes`;
`.unbounded` disables all guards and is for trusted input only (documented on
the API).
