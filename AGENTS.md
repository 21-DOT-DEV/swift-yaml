# swift-yaml — repository guide

`swift-yaml` wraps [yaml-cpp](https://github.com/jbeder/yaml-cpp) (a C++
YAML 1.2 parser/emitter) as a SwiftPM package. Upstream sources are
**vendored** with [vendir](https://carvel.dev/vendir), pinned to a release
tag (currently `yaml-cpp-0.6.2`).

## Never edit vendored files

Everything under `Sources/yamlcpp/{include,src,legal}/` is owned by
`vendir sync` and is **overwritten** on the next sync — edits there are
silently lost. All adaptation goes in one of:

- `Package.swift` settings (defines, header search paths, excludes),
- authored files **outside** the managed tree — e.g. `Sources/yamlcppShims/`,
- `vendir.yml` include/exclude rules.

If a change seems to need a vendored-file edit, the real answer is a
Package.swift setting, a file outside the managed tree, or a vendir rule.

## Layout

- `Sources/yamlcpp/` — vendored yaml-cpp (C++ library target). Public
  headers in `include/`, sources + private headers in `src/`, upstream
  license in `legal/` (excluded from the build target).
- `Sources/yamlcppShims/` — **authored** C++ bridges for yaml-cpp's
  template-shaped surface (`Node::as<T>()`, `operator[]<Key>`) that Swift
  C++ interop cannot instantiate from Swift. Created on demand from the
  test's build diagnostics.
- `Tests/yamlcppTests/` — Swift smoke tests. The only target that enables
  C++ interop (`.interoperabilityMode(.Cxx)`); interop is viral and
  semver-major, so it never touches the library product.

## Verify

```sh
swift build
swift test
```

## Sync ritual (updating vendored sources)

```sh
vendir sync            # re-fetch upstream at the ref pinned in vendir.yml
swift build && swift test
```

There is no preserve/restore step: yaml-cpp needs no generated or
replacement files, so nothing authored lives inside the vendir-managed
`Sources/yamlcpp` tree. See `vendir.yml` for provenance and layout notes.
