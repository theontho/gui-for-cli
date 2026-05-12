#pragma once

#include "AppState.hpp"

#include <map>
#include <string>

void renderActionButton(
    AppState& state,
    const ActionView& action,
    const std::map<std::string, std::string>& values,
    const std::string& suffix
);
