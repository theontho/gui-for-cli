#pragma once

#include <filesystem>
#include <string>

struct Args {
  std::filesystem::path bundle;
  std::filesystem::path repoRoot;
  std::string locale = "en";
  bool benchmark = false;
  bool benchmarkFull = false;
  bool once = false;
  bool version = false;
};

Args parseArgs(int argc, char** argv);
std::string usage();
