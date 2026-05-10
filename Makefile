.DEFAULT_GOAL := help

APP_NAME ?= GUI for CLI
DOTNET ?= dotnet
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

.PHONY: help precheck setup-dev lint lint-locales validate-bundles ax-smoke ax-smoke-ios ax-smoke-windows ax-all format test test-webui test-windows-core build-windows-core build-windows publish-windows package-windows-msix build-cli run-cli web web-dev web-kill web-icons project build-ios-sim build-ios-device build-macos mac ios ios-device cloc clean ci ci-fast

##@ General

help: ## Show available make targets.
	@awk 'BEGIN {FS = ":.*## "; bold = sprintf("%c[1m", 27); section = sprintf("%c[1;35m", 27); cyan = sprintf("%c[36m", 27); reset = sprintf("%c[0m", 27); printf "%sAvailable targets:%s\n", bold, reset} /^##@ / {printf "%s%s%s\n", section, substr($$0, 5), reset; next} /^[a-zA-Z0-9_-]+:.*## / {printf "  %s%-18s%s %s\n", cyan, $$1, reset, $$2}' $(MAKEFILE_LIST)

##@ Setup

precheck: ## Run repository precheck diagnostics.
	swift run gui-for-cli precheck

setup-dev: ## Resolve dependencies, install Tuist, and register local dev hooks.
	swift package resolve
	./scripts/tuist.sh install
	python3 scripts/dev-register.py
	python3 scripts/setup-hooks.py

project: ## Generate the Xcode project/workspace with Tuist.
	./scripts/tuist.sh generate --no-open

##@ Quality

lint: ## Lint Swift source formatting.
	swift format lint --recursive Sources Tests Apps scripts Project.swift Tuist.swift

lint-locales: ## Lint bundle localization TOML files (pass STRICT=1 to fail on warnings).
	python3 scripts/lint-locales.py $(if $(STRICT),--strict,)

validate-bundles: ## Run bundle manifest + locale validation across Examples/* (STRICT=1 fails on warnings).
	@swift run gui-for-cli bundle validate $(if $(STRICT),--strict,) Examples/*

ax-smoke: ## Probe the running macOS dev app via Accessibility APIs (requires pyobjc + a11y permission).
	@/opt/homebrew/bin/python3 scripts/ax-smoke.py

ax-smoke-ios: ## Probe a booted iOS Simulator via the `axe` CLI (brew install cameroncooke/axe/axe).
	@/opt/homebrew/bin/python3 scripts/ax-smoke-ios.py

ax-smoke-windows: ## Run a static Windows UI Automation smoke check, or set LIVE=1 for a running app.
	pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/windows-ax-smoke.ps1 $(if $(LIVE),,-StaticOnly)

ax-all: ax-smoke ax-smoke-ios ## Run both macOS and iOS accessibility smoke tests.

format: ## Format Swift source files in place.
	swift format format --in-place --recursive Sources Tests Apps scripts Project.swift Tuist.swift

test: ## Run the Swift test suite.
	swift test --parallel

test-windows-core: ## Run Windows C# core parity tests.
	$(DOTNET) run --project Tests/GUIForCLIWindows.CoreTests/GUIForCLIWindows.CoreTests.csproj

build-windows-core: ## Build the Windows C# core library.
	$(DOTNET) build Sources/GUIForCLIWindows.Core/GUIForCLIWindows.Core.csproj

build-windows: ## Build all Windows .NET projects.
	$(DOTNET) build GUIForCLIWindows.sln -p:Platform=x64

publish-windows: ## Publish the native Windows app into out/windows-publish.
	$(DOTNET) publish Apps/Windows/GUIForCLIWindows/GUIForCLIWindows.csproj -c Release -o out/windows-publish -p:Platform=x64 -p:WindowsAppSDKSelfContained=true -p:SelfContained=true

package-windows-msix: ## Build an MSIX package. Set CERT=path/to/cert.pfx and CERT_PASSWORD for signed packages.
	pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/package-windows-msix.ps1 -DotNet "$(DOTNET)" $(if $(CERT),-CertificatePath "$(CERT)" -CertificatePassword "$(CERT_PASSWORD)",)

##@ CLI

build-cli: ## Build the CLI in release mode.
	swift build -c release

run-cli: ## Run the GUI-for-CLI command runner.
	swift run gui-for-cli run

##@ Web

web: ## Build and run the local Web UI for a bundle (set BUNDLE=Examples/WGSExtract PORT=8787).
	npm --prefix WebUI run build
	node WebUI/dist/server/main.js --bundle "$(abspath $(or $(BUNDLE),Examples/WGSExtract))" --port "$(or $(PORT),8787)"

web-dev: ## Run the Web UI with TypeScript watch, server restart, and browser reload.
	npm --prefix WebUI run dev -- --bundle "$(abspath $(or $(BUNDLE),Examples/WGSExtract))" --port "$(or $(PORT),8787)"

test-webui: ## Build and run the Web UI TypeScript tests.
	npm --prefix WebUI test

web-icons: ## Update vendored Web UI Bootstrap Icons assets from npm.
	npm --prefix WebUI run vendor-icons

web-kill: ## Kill all running local Web UI server instances.
	@set -eu; \
	bold="$$(printf '\033[1m')"; \
	green="$$(printf '\033[32m')"; \
	yellow="$$(printf '\033[33m')"; \
	red="$$(printf '\033[31m')"; \
	reset="$$(printf '\033[0m')"; \
	pids="$$(ps -axww -o pid=,args= | awk '$$2 ~ /(^|\/)node$$/ && $$0 ~ /WebUI\/dist\/server\/main\.js/ { print $$1 }' | sort -u)"; \
	if [ -z "$$pids" ]; then \
		printf "%sNo Web UI server instances are running.%s\n" "$$yellow" "$$reset"; \
		exit 0; \
	fi; \
	printf "%sKilling Web UI server instances:%s %s\n" "$$bold" "$$reset" "$$pids"; \
	for pid in $$pids; do \
		if kill "$$pid" 2>/dev/null; then \
			printf "  %sKilled%s PID %s\n" "$$green" "$$reset" "$$pid"; \
		else \
			printf "  %sFailed%s PID %s\n" "$$red" "$$reset" "$$pid" >&2; \
			failed=1; \
		fi; \
	done; \
	exit "$${failed:-0}"

##@ macOS

build-macos: project ## Build the macOS desktop app.
	xcodebuild -workspace GUIForCLI.xcworkspace -scheme GUIForCLIMac -configuration Debug -derivedDataPath "$(DERIVED_DATA_PATH)" -destination '$(MACOS_DESTINATION)' build CODE_SIGNING_ALLOWED=NO

mac: build-macos ## Build and run the macOS desktop app.
	open "$(MACOS_APP)"

##@ iOS

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

ios: build-ios-sim ## Build, install, and run on an iOS Simulator. Set IOS_SIMULATOR if needed.
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

ios-device: build-ios-device ## Build, install, and run on an iOS device. Set IOS_DEVICE to the device identifier.
	@test -n "$(IOS_DEVICE)" || (echo "Set IOS_DEVICE to an iOS device identifier from: xcrun devicectl list devices" >&2; exit 1)
	xcrun devicectl device install app --device "$(IOS_DEVICE)" "$(IOS_DEVICE_APP)"
	xcrun devicectl device process launch --device "$(IOS_DEVICE)" "$(IOS_BUNDLE_ID)"

##@ Maintenance

clean: ## Remove SwiftPM, Tuist, build, and temporary outputs.
	swift package clean
	rm -rf GUIForCLI.xcodeproj GUIForCLI.xcworkspace Derived DerivedData .build
	rm -rf out/* tmp/*

cloc: ## Count lines of code, excluding gitignored files.
	@command -v cloc >/dev/null 2>&1 || (echo "cloc not found. Install with: brew install cloc" >&2; exit 1)
	cloc --vcs=git .

##@ CI

ci: ## Run the full CI pipeline locally (mirrors .github/workflows/ci.yml).
	python3 scripts/ci-local.py

ci-fast: ## Run the CI pipeline locally, skipping the iOS build.
	python3 scripts/ci-local.py --fast
