#pragma once

#include "AppState.hpp"

#include <string>

inline std::string localizedLabel(AppState& state, const std::string& key) {
  auto found = state.bundle.strings.find(key);
  return found == state.bundle.strings.end() ? key : found->second;
}
