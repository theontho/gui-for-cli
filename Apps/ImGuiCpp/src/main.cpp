#include "AppState.hpp"
#include "Args.hpp"
#include "Bundle.hpp"
#include "Renderer.hpp"

#include <chrono>
#include <iostream>

namespace {

int run(int argc, char** argv) {
  auto started = std::chrono::steady_clock::now();
  auto args = parseArgs(argc, argv);
  if (args.version) {
    std::cout << "gui-for-cli-imgui-cpp 0.1.0\n";
    return 0;
  }

  auto bundle = loadBundle(args.bundle, args.repoRoot, args.locale);
  auto loaded = std::chrono::steady_clock::now();
  AppState state(std::move(bundle), args);
  auto ready = std::chrono::steady_clock::now();

  std::optional<double> fullFeatureWarmMs;
  if (args.benchmark && args.benchmarkFull) {
    auto warmStarted = std::chrono::steady_clock::now();
    state.warmAllPages();
    fullFeatureWarmMs = std::chrono::duration<double, std::milli>(
                            std::chrono::steady_clock::now() - warmStarted
    )
                            .count();
  }

  if (args.benchmark) {
    auto loadedMs = std::chrono::duration<double, std::milli>(loaded - started).count();
    auto readyMs = std::chrono::duration<double, std::milli>(ready - started).count();
    std::cout << "gfc-imgui-cpp benchmark bundle_loaded_ms=" << loadedMs
              << " ui_ready_ms=" << readyMs;
    if (fullFeatureWarmMs) {
      std::cout << " full_feature_warm_ms=" << *fullFeatureWarmMs;
    }
    std::cout
              << " pages=" << state.bundle.pages.size()
              << " controls=" << state.bundle.controlCount
              << " actions=" << state.bundle.actionCount
              << " setup_steps=" << state.bundle.setupSteps.size()
              << " data_sources=" << state.bundle.dataSourceCount
              << " data_sources_loaded=" << state.dataSourcesLoaded()
              << " terminal_text_direction=" << state.bundle.terminalTextDirection << "\n";
  }

  if (args.once) {
    return 0;
  }

  runRenderer(state);
  return 0;
}

}  // namespace

int main(int argc, char** argv) {
  try {
    return run(argc, argv);
  } catch (const std::exception& error) {
    std::cerr << "gui-for-cli-imgui-cpp: " << error.what() << "\n";
    return 1;
  }
}
