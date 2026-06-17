#ifndef YAMLCPP_SHIMS_H
#define YAMLCPP_SHIMS_H

#include <cstddef>
#include <string>

#include "yaml-cpp/yaml.h"

// Authored bridges (NOT vendored — this lives outside the vendir-managed
// Sources/yamlcpp tree). yaml-cpp's value access is template-shaped
// (operator[]<Key>, Node::as<T>()), which Swift C++ interop cannot instantiate
// from Swift — `swift build` reports "could not generate C++ types from the
// generic Swift types provided" for both. Each helper performs the template
// instantiation here in C++ and exposes a non-template, value-returning
// signature interop can call. The set below is exactly what the smoke test's
// diagnostics demanded — nothing speculative.
namespace yamlx {

// operator[] is a member template; pin the two instantiations the smoke needs.
inline YAML::Node at(const YAML::Node &node, const char *key) {
  return node[key];
}

inline YAML::Node atIndex(const YAML::Node &node, std::size_t index) {
  return node[index];
}

// Node::as<T>() is a member template; one wrapper per needed instantiation.
inline long long asInt(const YAML::Node &node) {
  return node.as<long long>();
}

inline std::string asString(const YAML::Node &node) {
  return node.as<std::string>();
}

}  // namespace yamlx

#endif  // YAMLCPP_SHIMS_H
