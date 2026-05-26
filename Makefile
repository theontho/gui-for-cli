.DEFAULT_GOAL := help

APPLE_DIR := platform/apple
SWIFT_GIT_ENV := GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all
PYTHON ?= uv run python
PLATFORM_RUNNER := $(PYTHON) tools/platform.py
CI_CLI := $(PYTHON) tools/ci/ci_local.py
DEFAULT_BUNDLE ?= examples/WGSExtract
BUNDLE ?= $(DEFAULT_BUNDLE)
RELEASE_DIR ?= out/release

RUNNER_ARGS := $(strip $(PLATFORM) $(if $(SUITE),suite:$(SUITE),) $(ARGS))

export DEFAULT_BUNDLE BUNDLE PORT RELEASE_DIR SAMPLES HEADLESS NO_FOCUS CAPTURE_ONLY LAUNCH_ARGS
export IOS_SIMULATOR IOS_IPAD_SIMULATOR IOS_DEVICE IOS_SIM_DESTINATION IOS_DEVICE_DESTINATION MACOS_DESTINATION
export FLUTTER_WINDOW_WIDTH FLUTTER_WINDOW_HEIGHT TEXTUAL_ARGS TKINTER_ARGS WX_ARGS

.PHONY: \
	help platforms \
	setup build run test clean clean-deep benchmark screenshot package release-build \
	precheck lint format \
	ax-smoke ax-smoke-ios \
	cloc ci ci-fast

##@ General

help: ## Show the new runner-based command surface.
	@printf '%s\n' 'Usage:'
	@printf '  %s\n' 'make <action> PLATFORM=<name>'
	@printf '  %s\n' 'make <action> SUITE=<name>'
	@printf '  %s\n' 'make benchmark ARGS="macos"'
	@printf '  %s\n' 'make screenshot ARGS="macos"'
	@printf '\n%s\n' 'Actions: setup lint format build run test clean benchmark screenshot package release-build'
	@printf '\n%s\n' 'Examples:'
	@printf '  %s\n' 'make build PLATFORM=swiftui-macos'
	@printf '  %s\n' 'make run PLATFORM=webui'
	@printf '  %s\n' 'make test SUITE=stable'
	@printf '  %s\n' 'make release-build SUITE=stable'
	@printf '  %s\n' 'make package PLATFORM=webui'
	@printf '\n%s\n' 'Run `make platforms` for available platforms and suites.'

platforms: ## List runner actions, suites, and platforms.
	$(PLATFORM_RUNNER) list

##@ Platform Runner

setup: ## Run setup for PLATFORM=<name> or SUITE=<name>.
	$(PLATFORM_RUNNER) setup $(RUNNER_ARGS)

lint: ## Lint PLATFORM=<name> or SUITE=<name> (defaults to stable).
	$(PLATFORM_RUNNER) lint $(RUNNER_ARGS)

format: ## Format PLATFORM=<name> or SUITE=<name> (defaults to all).
	$(PLATFORM_RUNNER) format $(RUNNER_ARGS)

build: ## Build PLATFORM=<name> or SUITE=<name>.
	$(PLATFORM_RUNNER) build $(RUNNER_ARGS)

run: ## Run PLATFORM=<name> or SUITE=<name>.
	$(PLATFORM_RUNNER) run $(RUNNER_ARGS)

test: ## Test PLATFORM=<name> or SUITE=<name>.
	$(PLATFORM_RUNNER) test $(RUNNER_ARGS)

clean: ## Clean PLATFORM=<name> or SUITE=<name> (defaults to all).
	$(PLATFORM_RUNNER) clean $(RUNNER_ARGS)

clean-deep: ## Aggressively delete ALL build/output/cache dirs (out/, DerivedData, target/, runtime data). Irreversible — recreates from source on next build.
	@printf '%s\n' 'clean-deep: removing large build/output/cache dirs (this can free many GB)'
	@rm -rf out tmp
	@rm -rf platform/apple/DerivedData platform/apple/.build platform/apple/.derivedData
	@rm -rf platform/typescript/dist platform/typescript/.cache
	@rm -rf platform/typescript/web/packagers/tauri/target
	@for d in exp-platform/rust/*/target exp-platform/rust/gpui/tmp; do \
		[ -d "$$d" ] && rm -rf "$$d" && echo "  removed $$d"; \
	done
	@rm -rf exp-platform/c/raygui/build exp-platform/cpp/imgui-cpp/build
	@rm -rf exp-platform/dart/flutter/build exp-platform/dart/flutter/.dart_tool
	@rm -rf exp-platform/kotlin/compose/build exp-platform/kotlin/compose/.gradle
	@for d in examples/*/output examples/*/reference examples/*/genomes examples/*/runtime examples/*/settings; do \
		[ -d "$$d" ] && rm -rf "$$d" && echo "  removed $$d"; \
	done
	@printf '%s\n' 'clean-deep: done'

benchmark: ## Run benchmark PLATFORM=<name>, SUITE=<name>, or ARGS="<suite-or-command>".
	$(PLATFORM_RUNNER) benchmark $(RUNNER_ARGS)

screenshot: ## Capture screenshot PLATFORM=<name>, SUITE=<name>, or ARGS="<suite-or-surface>".
	$(PLATFORM_RUNNER) screenshot $(RUNNER_ARGS)

package: ## Package PLATFORM=<name> or SUITE=<name>.
	$(PLATFORM_RUNNER) package $(RUNNER_ARGS)

release-build: ## Build release PLATFORM=<name> or SUITE=<name>.
	$(PLATFORM_RUNNER) release-build $(RUNNER_ARGS)

##@ Quality

precheck: ## Run repository precheck diagnostics.
	$(PYTHON) tools/precheck.py

ax-smoke: ## Run macOS accessibility smoke test against the running dev app.
	$(PYTHON) tools/accessibility/ax_smoke.py

ax-smoke-ios: ## Run iOS Simulator accessibility smoke test against the running dev app.
	$(PYTHON) tools/accessibility/ax_smoke_ios.py

cloc: ## Count lines of code, excluding gitignored files.
	@command -v cloc >/dev/null 2>&1 || (echo "cloc not found. Install with: brew install cloc" >&2; exit 1)
	cloc --vcs=git .

dup: ## Detect copy-paste duplication across source files (jscpd). HTML report in out/jscpd/.
	npx --prefix platform/typescript jscpd --config .jscpd.json .

dup-ci: ## Detect duplication with console-only reporter (CI-friendly).
	npx --prefix platform/typescript jscpd --config .jscpd.json --reporters console .

##@ CI

ci: ## Run the full CI pipeline locally (mirrors .github/workflows/ci.yml).
	$(CI_CLI)

ci-fast: ## Run the CI pipeline locally, skipping the iOS build.
	$(CI_CLI) --fast
