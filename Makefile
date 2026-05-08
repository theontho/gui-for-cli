.DEFAULT_GOAL := help

APP_NAME ?= GUI for CLI
DERIVED_DATA_PATH ?= DerivedData
IOS_BUNDLE_ID ?= dev.guiforcli.gui-for-cli.ios
IOS_SIMULATOR ?= booted
IOS_SIM_DESTINATION ?= generic/platform=iOS Simulator
IOS_DEVICE_DESTINATION ?= generic/platform=iOS
MACOS_DESTINATION ?= platform=macOS

MACOS_APP := $(DERIVED_DATA_PATH)/Build/Products/Debug/$(APP_NAME).app
IOS_SIM_APP := $(DERIVED_DATA_PATH)/Build/Products/Debug-iphonesimulator/$(APP_NAME).app
IOS_DEVICE_APP := $(DERIVED_DATA_PATH)/Build/Products/Debug-iphoneos/$(APP_NAME).app
IOS_SIM_DEMO_BUNDLE := $(IOS_SIM_APP)/gui-for-cli_GUIForCLICore.bundle/Resources/DemoBundles/WGSExtract
IOS_DEVICE_DEMO_BUNDLE := $(IOS_DEVICE_APP)/gui-for-cli_GUIForCLICore.bundle/Resources/DemoBundles/WGSExtract

.PHONY: help precheck setup-dev lint lint-locales validate-bundles ax-smoke format test build-cli run-cli project build-ios build-ios-sim build-ios-device build-macos run-macos run-ios-sim run-ios-device cloc clean

help: ## Show available make targets.
	@awk 'BEGIN {FS = ":.*## "; printf "Available targets:\n"} /^[a-zA-Z0-9_-]+:.*## / {printf "  %-14s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

precheck: ## Run repository precheck diagnostics.
	swift run gui-for-cli precheck

setup-dev: ## Resolve dependencies, install Tuist, and register local dev hooks.
	swift package resolve
	./scripts/tuist.sh install
	swift scripts/dev-register.swift
	swift scripts/setup-hooks.swift

lint: ## Lint Swift source formatting.
	swift format lint --recursive Sources Tests Apps scripts Project.swift Tuist.swift

lint-locales: ## Lint bundle localization TOML files (pass STRICT=1 to fail on warnings).
	swift scripts/lint-locales.swift $(if $(STRICT),--strict,)

validate-bundles: ## Run bundle manifest + locale validation across Examples/* (STRICT=1 fails on warnings).
	@swift run gui-for-cli bundle validate $(if $(STRICT),--strict,) Examples/*

ax-smoke: ## Probe the running macOS dev app via Accessibility APIs (requires pyobjc + a11y permission).
	@/opt/homebrew/bin/python3 scripts/ax-smoke.py

format: ## Format Swift source files in place.
	swift format format --in-place --recursive Sources Tests Apps scripts Project.swift Tuist.swift

test: ## Run the Swift test suite.
	swift test --parallel

build-cli: ## Build the CLI in release mode.
	swift build -c release

run-cli: ## Run the GUI-for-CLI command runner.
	swift run gui-for-cli run

project: ## Generate the Xcode project/workspace with Tuist.
	./scripts/tuist.sh generate --no-open

build-ios: build-ios-sim ## Alias for build-ios-sim.

build-ios-sim: project ## Build the iOS simulator app.
	xcodebuild -workspace GUIForCLI.xcworkspace -scheme GUIForCLIiOS -configuration Debug -derivedDataPath "$(DERIVED_DATA_PATH)" -destination '$(IOS_SIM_DESTINATION)' build CODE_SIGNING_ALLOWED=NO
	@if [ -L "$(IOS_SIM_DEMO_BUNDLE)" ]; then \
		echo "Materializing WGSExtract demo bundle for iOS simulator install"; \
		rm "$(IOS_SIM_DEMO_BUNDLE)"; \
		ditto "Examples/WGSExtract" "$(IOS_SIM_DEMO_BUNDLE)"; \
	fi

build-ios-device: project ## Build the iOS device app. Optionally set IOS_DEVICE_DESTINATION.
	xcodebuild -workspace GUIForCLI.xcworkspace -scheme GUIForCLIiOS -configuration Debug -derivedDataPath "$(DERIVED_DATA_PATH)" -destination '$(IOS_DEVICE_DESTINATION)' build
	@if [ -L "$(IOS_DEVICE_DEMO_BUNDLE)" ]; then \
		echo "Materializing WGSExtract demo bundle for iOS device install"; \
		rm "$(IOS_DEVICE_DEMO_BUNDLE)"; \
		ditto "Examples/WGSExtract" "$(IOS_DEVICE_DEMO_BUNDLE)"; \
	fi

build-macos: project ## Build the macOS desktop app.
	xcodebuild -workspace GUIForCLI.xcworkspace -scheme GUIForCLIMac -configuration Debug -derivedDataPath "$(DERIVED_DATA_PATH)" -destination '$(MACOS_DESTINATION)' build CODE_SIGNING_ALLOWED=NO

run-macos: build-macos ## Build and run the macOS desktop app.
	open "$(MACOS_APP)"

run-ios-sim: build-ios-sim ## Build, install, and run on an iOS Simulator. Set IOS_SIMULATOR if needed.
	@set -eu; \
	simulator="$(IOS_SIMULATOR)"; \
	if [ "$$simulator" = "booted" ]; then \
		simulator="$$(xcrun simctl list devices booted | sed -nE 's/.*\(([0-9A-F-]{36})\) \(Booted\).*/\1/p' | head -n 1)"; \
		if [ -z "$$simulator" ]; then \
			simulator="$$(xcrun simctl list devices available | sed -nE '/iPhone|iPad/s/.*\(([0-9A-F-]{36})\) \(Shutdown\).*/\1/p' | head -n 1)"; \
			if [ -z "$$simulator" ]; then \
				echo "No booted or available iOS simulators found. Set IOS_SIMULATOR to a simulator UDID or name." >&2; \
				exit 1; \
			fi; \
			echo "No simulator is booted; booting $$simulator"; \
			xcrun simctl boot "$$simulator" || true; \
		fi; \
	else \
		xcrun simctl boot "$$simulator" || true; \
	fi; \
	xcrun simctl bootstatus "$$simulator" -b; \
	xcrun simctl install "$$simulator" "$(IOS_SIM_APP)"; \
	xcrun simctl launch "$$simulator" "$(IOS_BUNDLE_ID)"

run-ios-device: build-ios-device ## Build, install, and run on an iOS device. Set IOS_DEVICE to the device identifier.
	@test -n "$(IOS_DEVICE)" || (echo "Set IOS_DEVICE to an iOS device identifier from: xcrun devicectl list devices" >&2; exit 1)
	xcrun devicectl device install app --device "$(IOS_DEVICE)" "$(IOS_DEVICE_APP)"
	xcrun devicectl device process launch --device "$(IOS_DEVICE)" "$(IOS_BUNDLE_ID)"

clean: ## Remove SwiftPM, Tuist, build, and temporary outputs.
	swift package clean
	rm -rf GUIForCLI.xcodeproj GUIForCLI.xcworkspace Derived DerivedData .build
	rm -rf out/* tmp/*

cloc: ## Count lines of code, excluding gitignored files.
	@command -v cloc >/dev/null 2>&1 || (echo "cloc not found. Install with: brew install cloc" >&2; exit 1)
	cloc --vcs=git .
