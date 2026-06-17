#ifndef YAMLCPP_SHIMS_H
#define YAMLCPP_SHIMS_H

#include <cstddef>
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

// Scalar text by value (Scalar() returns a const reference — copy it out so no
// Swift String aliases yaml-cpp storage). Empty string for a non-scalar node.
inline std::string scalarText(const Node &node) {
  try {
    if (node.IsScalar()) {
      return node.Scalar();
    }
  } catch (...) {
  }
  return std::string();
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

// i-th map key, as scalar text. Empty string if absent / non-scalar key.
// Index-based access advances the iterator each call (O(n) per call); the
// overlay materializes a map once and bounds total work with its node budget.
inline std::string mapKeyText(const Node &node, long index) {
  try {
    if (!node.IsMap()) return std::string();
    long i = 0;
    for (YAML::const_iterator it = node.begin(); it != node.end(); ++it, ++i) {
      if (i == index) {
        if (it->first.IsScalar()) return it->first.Scalar();
        return std::string();
      }
    }
  } catch (...) {
  }
  return std::string();
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

inline std::string emitterError(void *p) {
  return static_cast<YAML::Emitter *>(p)->GetLastError();
}

inline std::string emitterText(void *p) {
  const char *s = static_cast<YAML::Emitter *>(p)->c_str();
  return s ? std::string(s) : std::string();
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
