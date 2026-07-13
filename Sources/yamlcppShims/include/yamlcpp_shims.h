#ifndef YAMLCPP_SHIMS_H
#define YAMLCPP_SHIMS_H

#include <cstddef>
#include <cstring>
#include <string>

#include "yaml-cpp/yaml.h"
#include "yaml-cpp/emitter.h"
#include "yaml-cpp/node/emit.h"

// Authored bridges (NOT vendored — this lives outside the vendir-managed
// Sources/yamlcpp tree). yaml-cpp's value access is template-shaped
// (operator[]<Key>, Node::as<T>()), which Swift C++ interop cannot instantiate
// from Swift — `swift build` reports "could not generate C++ types from the
// generic Swift types provided" for both. Each helper performs the template
// instantiation here in C++ and exposes a non-template, value-returning
// signature interop can call.
//
// SAFETY (critical): Swift C++ interop imports C++ functions as *non-throwing*.
// A C++ exception that escapes a helper into Swift is undefined behavior — in
// practice a crash, std::terminate, or a hang. yaml-cpp throws liberally
// (Load on malformed input, as<T>() on bad conversion, Scalar()/operator[] on
// type mismatch). Therefore EVERY helper below that touches throwing yaml-cpp
// surface wraps its body in `try { ... } catch (...)` and signals failure as a
// *value* (a ParseResult.ok flag, an empty string, an undefined Node). The
// Swift overlay reads that signaled failure and raises an idiomatic typed
// `throw` (DecodingError / YAMLError). Errors cross the boundary as data, not
// as C++ exceptions.
namespace yamlx {

// A Swift-friendly alias so the overlay never has to spell the bare `YAML`
// C++ namespace (which would collide with the Swift product module also named
// `YAML`). The overlay refers to nodes as `yamlx.Node`.
using Node = YAML::Node;

// A NUL-safe, non-owning view of C++-side string bytes handed to Swift: a
// `const char*` plus an explicit byte length. The overlay copies these bytes into
// a Swift String immediately (via `String.init(_: yamlx.CStr)` in YAMLSerialization),
// so `data` only needs to stay valid for the duration of that single call.
//
// This type is the whole reason the string helpers below return a view instead of
// a `std::string`: a `std::string` must NEVER cross into Swift as a value. Doing so
// requires the CxxStdlib overlay's `String(_: std.string)` initializer (or the Cxx
// module's `std.string` Collection conformance) to be in scope during overload
// resolution — and under whole-module / multi-file-batch compilation on macOS those
// conformances silently drop out (forums.swift.org/t/74393), so `String(someStdString)`
// fails with "no exact matches in call to initializer": only on macOS CI, only in
// whole-module mode. Returning `const char*` + length keeps std::string entirely on
// the C++ side; Swift converts via stdlib pointer APIs, which are always available.
// See Projects/README.md for the full diagnosis.
struct CStr {
  const char *data;
  long len;
};

// ---------------------------------------------------------------------------
// Legacy smoke-test helpers (kept for Tests/yamlcppTests). These call the
// throwing as<T>() and MUST NOT be used by the overlay on untrusted input —
// the overlay uses the guarded scalarText()/parse() path below instead.
// ---------------------------------------------------------------------------

inline YAML::Node at(const YAML::Node &node, const char *key) {
  return node[key];
}

inline YAML::Node atIndex(const YAML::Node &node, std::size_t index) {
  return node[index];
}

inline long long asInt(const YAML::Node &node) {
  return node.as<long long>();
}

inline std::string asString(const YAML::Node &node) {
  return node.as<std::string>();
}

// ---------------------------------------------------------------------------
// Decode boundary: text -> node tree, then non-throwing inspection.
// ---------------------------------------------------------------------------

// Result of a guarded parse. `ok == false` means the input was malformed and
// `message`/`line`/`column` describe the failure (line/column are 0-based, as
// yaml-cpp reports them; the overlay adds 1 for human display).
struct ParseResult {
  bool ok;
  Node root;
  long line;
  long column;
  std::string message;
};

inline ParseResult parse(const char *input) {
  ParseResult r;
  r.ok = false;
  r.line = -1;
  r.column = -1;
  try {
    r.root = YAML::Load(input);
    r.ok = true;
  } catch (const YAML::Exception &e) {
    // ParserException and the representation exceptions all derive from
    // Exception, which carries a Mark (line/column) and a message.
    r.message = e.msg;
    r.line = static_cast<long>(e.mark.line);
    r.column = static_cast<long>(e.mark.column);
  } catch (const std::exception &e) {
    r.message = e.what();
  } catch (...) {
    r.message = "unknown YAML parse error";
  }
  return r;
}

// NUL-safe view of a failed parse's error message (see `CStr`). The message lives
// in the Swift-held ParseResult, so the view is valid for as long as Swift holds
// that value — no copy needed.
inline CStr parseMessage(const ParseResult &r) {
  return CStr{r.message.data(), static_cast<long>(r.message.size())};
}

// 0 undefined / 1 null / 2 scalar / 3 sequence / 4 map. Type() does not throw.
inline int nodeKind(const Node &node) {
  switch (node.Type()) {
    case YAML::NodeType::Null:
      return 1;
    case YAML::NodeType::Scalar:
      return 2;
    case YAML::NodeType::Sequence:
      return 3;
    case YAML::NodeType::Map:
      return 4;
    case YAML::NodeType::Undefined:
    default:
      return 0;
  }
}

// Number of children: sequence elements or map pairs. size() does not throw.
inline long count(const Node &node) {
  return static_cast<long>(node.size());
}

// Scalar text as a NUL-safe view (see `CStr`). Scalar() returns a const reference;
// we copy it into thread-local storage the view points at, so nothing Swift-side
// aliases yaml-cpp's node storage and no std::string crosses the boundary. Empty
// view for a non-scalar node. The view is valid until the next scalarText() call on
// the same thread; the overlay converts to String before the next call.
inline CStr scalarText(const Node &node) {
  static thread_local std::string buf;
  buf.clear();
  try {
    if (node.IsScalar()) {
      buf = node.Scalar();
    }
  } catch (...) {
  }
  return CStr{buf.data(), static_cast<long>(buf.size())};
}

// The node's tag (e.g. "?", "!", "tag:yaml.org,2002:str"); used only for null
// disambiguation. Never throws here; guarded anyway.
inline std::string nodeTag(const Node &node) {
  try {
    return node.Tag();
  } catch (...) {
    return std::string();
  }
}

// i-th sequence element. Undefined Node on any error (Swift treats it as null).
inline Node seqItem(const Node &node, long index) {
  try {
    return node[static_cast<std::size_t>(index)];
  } catch (...) {
    return Node();
  }
}

// i-th map key, as a NUL-safe scalar-text view (see `CStr`). Empty view if absent /
// non-scalar key. Index-based access advances the iterator each call (O(n) per call);
// the overlay materializes a map once and bounds total work with its node budget.
inline CStr mapKeyText(const Node &node, long index) {
  static thread_local std::string buf;
  buf.clear();
  try {
    if (node.IsMap()) {
      long i = 0;
      for (YAML::const_iterator it = node.begin(); it != node.end(); ++it, ++i) {
        if (i == index) {
          if (it->first.IsScalar()) buf = it->first.Scalar();
          break;
        }
      }
    }
  } catch (...) {
  }
  return CStr{buf.data(), static_cast<long>(buf.size())};
}

// i-th map value. Undefined Node on any error.
inline Node mapValue(const Node &node, long index) {
  try {
    if (!node.IsMap()) return Node();
    long i = 0;
    for (YAML::const_iterator it = node.begin(); it != node.end(); ++it, ++i) {
      if (i == index) return it->second;
    }
  } catch (...) {
  }
  return Node();
}

// ---------------------------------------------------------------------------
// Source position & span (Phase 3, feature 3). yaml-cpp records where each node
// STARTS (Node::Mark()) but never where it ends; computing the end is ours.
// Both helpers return plain integers by value, so Swift imports the structs as
// safe (escapable) value types needing no interop lifetime annotations — unlike
// the CStr view above, they carry no borrowed memory. See
// Specs/001-mark-span-shim/plan.md for the full design and review history.
// ---------------------------------------------------------------------------

// A node's start position. ok == false means the node was invalid or undefined:
// Node::Mark() throws InvalidNode on an invalid node (guarded here) and returns
// null_mark() (-1,-1,-1) for an undefined one. pos is a 0-based byte offset into
// the decoded UTF-8 stream; line/column are 0-based as yaml-cpp reports them
// (the overlay adds 1 to line/column for human display).
struct Mark {
  bool ok;
  long pos;
  long line;
  long column;
};

inline Mark mark(const Node &node) {
  Mark m{false, -1, -1, -1};
  try {
    YAML::Mark k = node.Mark();  // throws InvalidNode on an invalid node
    if (k.is_null()) return m;   // undefined/empty node -> ok stays false
    m = Mark{true, static_cast<long>(k.pos), static_cast<long>(k.line),
             static_cast<long>(k.column)};
  } catch (...) {
  }
  return m;
}

// A scalar value's source span. `end` / `endReliable` are meaningful ONLY when
// endReliable == true: a plain, unquoted, single-line scalar whose SOURCE bytes
// equal its parsed bytes. Reliability is *verified against the source*, not
// guessed — yaml-cpp discards scalar style on parse, so Node::Style() cannot
// tell plain from quoted. Three guards make endReliable a proven property:
//   * source[pos] is not a scalar-style indicator (' " | >). A quoted/block
//     scalar always marks AT its indicator, and a plain scalar can never begin
//     with one, so this is the real plain-vs-quoted discriminator. It alone
//     rejects a quoted value that begins with its own wrapper quote (k: ''''
//     -> ' ), which a bare byte compare would wrongly accept.
//   * n > 0: std::memcmp(_, _, 0) is vacuously equal, which would otherwise mark
//     an empty quoted/block scalar reliable (empty plain scalars parse as null).
//   * the n source bytes at pos equal the parsed value exactly (single line).
// Any mismatch (quotes, escapes, block/folded, multi-line, or a pos/byte skew
// from a BOM or CRLF input) leaves endReliable == false and the caller falls
// back. `source`/`len` are the original document bytes (read-only, not retained).
struct Span {
  bool ok;
  long pos;
  long line;
  long column;
  long end;
  bool endReliable;
};

inline Span valueSpan(const Node &node, const char *source, long len) {
  Mark m = mark(node);
  Span s{m.ok, m.pos, m.line, m.column, -1, false};
  if (!m.ok) return s;
  try {
    if (node.IsScalar() && source != nullptr && m.pos >= 0) {
      const std::string &v = node.Scalar();
      long n = static_cast<long>(v.size());
      if (n > 0 &&                                 // non-empty: memcmp(_,_,0) is vacuously equal
          m.pos + n <= len &&
          v.find('\n') == std::string::npos &&     // single line
          source[m.pos] != '\'' && source[m.pos] != '"' &&   // not single/double quoted
          source[m.pos] != '|' && source[m.pos] != '>' &&    // not literal/folded block
          std::memcmp(source + m.pos, v.data(), static_cast<std::size_t>(n)) == 0) {  // verbatim
        s.end = m.pos + n;
        s.endReliable = true;
      }
    }
  } catch (...) {
  }
  return s;
}

// ---------------------------------------------------------------------------
// Encode boundary: event-streamed YAML::Emitter.
//
// Scalar quoting cannot be controlled through the node tree (EmitterStyle has
// only Default/Block/Flow — no scalar-quote axis), so the overlay drives the
// emitter event by event and chooses quoting per scalar with the DoubleQuoted
// manipulator. The emitter is held by Swift as an opaque `void*` handle for
// the duration of one encode() call (no raw C++ type crosses into the public
// API). Every op is guarded: the emitter throws EmitterException on a
// malformed event sequence.
// ---------------------------------------------------------------------------

inline void *newEmitter() { return static_cast<void *>(new YAML::Emitter()); }

inline void freeEmitter(void *p) {
  delete static_cast<YAML::Emitter *>(p);
}

inline void emitterSetIndent(void *p, long n) {
  if (n > 0) static_cast<YAML::Emitter *>(p)->SetIndent(static_cast<std::size_t>(n));
}

inline bool emitterOK(void *p) {
  return static_cast<YAML::Emitter *>(p)->good();
}

// The emitter's last error, as a NUL-safe view (see `CStr`). GetLastError() returns
// a std::string by value; copy it into thread-local storage the view points at.
inline CStr emitterError(void *p) {
  static thread_local std::string buf;
  try {
    buf = static_cast<YAML::Emitter *>(p)->GetLastError();
  } catch (...) {
    buf.clear();
  }
  return CStr{buf.data(), static_cast<long>(buf.size())};
}

// The emitted document text, as a NUL-safe view (see `CStr`). Emitter::c_str() is a
// stable, NUL-terminated buffer owned by the emitter — valid until the emitter is
// freed — so no copy is needed; size() gives the exact byte length. The overlay
// converts to String before it frees the emitter.
inline CStr emitterText(void *p) {
  YAML::Emitter *e = static_cast<YAML::Emitter *>(p);
  const char *s = e->c_str();
  return CStr{s ? s : "", s ? static_cast<long>(e->size()) : 0};
}

inline void beginMap(void *p, bool flow) {
  YAML::Emitter *e = static_cast<YAML::Emitter *>(p);
  try {
    if (flow) *e << YAML::Flow;
    *e << YAML::BeginMap;
  } catch (...) {
  }
}

inline void endMap(void *p) {
  try { *static_cast<YAML::Emitter *>(p) << YAML::EndMap; } catch (...) {}
}

inline void beginSeq(void *p, bool flow) {
  YAML::Emitter *e = static_cast<YAML::Emitter *>(p);
  try {
    if (flow) *e << YAML::Flow;
    *e << YAML::BeginSeq;
  } catch (...) {
  }
}

inline void endSeq(void *p) {
  try { *static_cast<YAML::Emitter *>(p) << YAML::EndSeq; } catch (...) {}
}

inline void emitKeyToken(void *p) {
  try { *static_cast<YAML::Emitter *>(p) << YAML::Key; } catch (...) {}
}

inline void emitValueToken(void *p) {
  try { *static_cast<YAML::Emitter *>(p) << YAML::Value; } catch (...) {}
}

inline void emitNull(void *p) {
  try { *static_cast<YAML::Emitter *>(p) << YAML::Null; } catch (...) {}
}

// A plain scalar (numbers, booleans, null tokens already formatted by Swift).
// yaml-cpp still applies syntactic quoting if the text would be unsafe plain.
inline void emitPlainScalar(void *p, const char *s) {
  try { *static_cast<YAML::Emitter *>(p) << std::string(s); } catch (...) {}
}

// A double-quoted scalar, for strings the overlay must keep typed as strings
// (text that would otherwise resolve to a number/bool/null).
inline void emitQuotedScalar(void *p, const char *s) {
  try {
    *static_cast<YAML::Emitter *>(p) << YAML::DoubleQuoted << std::string(s);
  } catch (...) {
  }
}

}  // namespace yamlx

#endif  // YAMLCPP_SHIMS_H
