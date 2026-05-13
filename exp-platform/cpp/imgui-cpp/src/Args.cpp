#include "Args.hpp"

#include <stdexcept>
#include <vector>

namespace {

std::filesystem::path findRepoRoot(std::filesystem::path start) {
  while (!start.empty()) {
    if (std::filesystem::exists(start / "platform" / "apple" / "Package.swift") &&
        std::filesystem::exists(start / "examples")) {
      return start;
    }
    auto parent = start.parent_path();
    if (parent == start) {
      break;
    }
    start = parent;
  }
  return std::filesystem::current_path();
}

std::string nextOptionValue(
    const std::vector<std::string>& raw,
    std::size_t& index,
    const std::string& flag
) {
  if (index + 1 >= raw.size() || raw[index + 1].starts_with("-")) {
    throw std::runtime_error(flag + " requires a value");
  }
  index += 1;
  return raw[index];
}

}  // namespace

Args parseArgs(int argc, char** argv) {
  Args args;
  args.repoRoot = findRepoRoot(std::filesystem::current_path());
  args.bundle = args.repoRoot / "examples" / "WGSExtract";

  std::vector<std::string> raw;
  raw.reserve(static_cast<std::size_t>(argc));
  for (int index = 1; index < argc; ++index) {
    raw.emplace_back(argv[index]);
  }

  bool bundleWasProvided = false;
  for (std::size_t index = 0; index < raw.size(); ++index) {
    const auto& argument = raw[index];
    if (argument == "--bundle") {
      bundleWasProvided = true;
      args.bundle = nextOptionValue(raw, index, argument);
    } else if (argument == "--repo-root") {
      args.repoRoot = nextOptionValue(raw, index, argument);
      if (!bundleWasProvided) {
        args.bundle = args.repoRoot / "examples" / "WGSExtract";
      }
    } else if (argument == "--locale") {
      args.locale = nextOptionValue(raw, index, argument);
    } else if (argument == "--benchmark") {
      args.benchmark = true;
    } else if (argument == "--benchmark-full") {
      args.benchmarkFull = true;
    } else if (argument == "--once") {
      args.once = true;
    } else if (argument == "--version") {
      args.version = true;
    } else if (argument == "--help" || argument == "-h") {
      throw std::runtime_error(usage());
    } else {
      throw std::runtime_error("unknown argument: " + argument + "\n" + usage());
    }
  }

  return args;
}

std::string usage() {
  return "Usage: gui-for-cli-imgui-cpp [--bundle PATH] [--repo-root PATH] "
         "[--locale CODE] [--benchmark] [--benchmark-full] [--once] [--version]";
}
