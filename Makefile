.DEFAULT_GOAL := help

APP_NAME ?= GUI for CLI
APPKIT_APP_NAME ?= swift appkit test
OBJC_APPKIT_APP_NAME ?= GUI for CLI ObjC AppKit Test
DERIVED_DATA_PATH ?= DerivedData
RELEASE_DIR ?= out/release
IOS_BUNDLE_ID ?= dev.guiforcli.gui-for-cli.ios
IOS_SIMULATOR ?= booted
IOS_SIM_DESTINATION ?= generic/platform=iOS Simulator
IOS_DEVICE_DESTINATION ?= generic/platform=iOS
MACOS_DESTINATION ?= platform=macOS

MACOS_APP := $(DERIVED_DATA_PATH)/Build/Products/Debug/$(APP_NAME).app
MACOS_APPKIT_APP := $(DERIVED_DATA_PATH)/Build/Products/Debug/$(APPKIT_APP_NAME).app
MACOS_RELEASE_APP := $(DERIVED_DATA_PATH)/Build/Products/Release/$(APP_NAME).app
MACOS_APPKIT_RELEASE_APP := $(DERIVED_DATA_PATH)/Build/Products/Release/$(APPKIT_APP_NAME).app
OBJC_APPKIT_APP := $(DERIVED_DATA_PATH)/Build/Products/Debug/$(OBJC_APPKIT_APP_NAME).app
OBJC_APPKIT_EXE := $(OBJC_APPKIT_APP)/Contents/MacOS/$(OBJC_APPKIT_APP_NAME)
IOS_SIM_APP := $(DERIVED_DATA_PATH)/Build/Products/Debug-iphonesimulator/$(APP_NAME).app
IOS_DEVICE_APP := $(DERIVED_DATA_PATH)/Build/Products/Debug-iphoneos/$(APP_NAME).app
IOS_SIM_DEMO_BUNDLE := $(IOS_SIM_APP)/gui-for-cli_GUIForCLICore.bundle/Resources/DemoBundles/WGSExtract
IOS_DEVICE_DEMO_BUNDLE := $(IOS_DEVICE_APP)/gui-for-cli_GUIForCLICore.bundle/Resources/DemoBundles/WGSExtract
WEBUI_RELEASE_DIR := $(RELEASE_DIR)/webui
SWIFT_RELEASE_DIR := $(RELEASE_DIR)/swift
APPKIT_RELEASE_DIR := $(RELEASE_DIR)/appkit
WEBVIEW_RELEASE_DIR := $(RELEASE_DIR)/webview
TAURI_RELEASE_DIR := $(RELEASE_DIR)/tauri
ELECTRON_RELEASE_DIR := $(RELEASE_DIR)/electron
DIOXUS_RELEASE_DIR := $(RELEASE_DIR)/dioxus
RUST_APPS_DIR := Apps/DioxusShell
RUST_APP_EXE := $(RUST_APPS_DIR)/target/release/gui-for-cli-webui-dioxus
SLINT_RELEASE_DIR := $(RELEASE_DIR)/slint
RAYGUI_RELEASE_DIR := $(RELEASE_DIR)/raygui
FLUTTER_RELEASE_DIR := $(RELEASE_DIR)/flutter
GIO_RELEASE_DIR := $(RELEASE_DIR)/gio
FLUTTER_BENCHMARK_OUTPUT ?= /tmp/gui-for-cli-flutter-benchmark.txt
FLUTTER_WINDOW_WIDTH ?= 1344
FLUTTER_WINDOW_HEIGHT ?= 864
GIO_GO ?= GOTOOLCHAIN=go1.24.13 go
WEBVIEW_SHELL_APP := $(DERIVED_DATA_PATH)/WebViewShell/GUI for CLI WebView Shell.app
WEBVIEW_SHELL_EXE := $(WEBVIEW_SHELL_APP)/Contents/MacOS/GUIForCLIWebViewShell
WEBUI_TAURI_APP := WebUI/src-tauri/target/release/bundle/macos/GUI for CLI WebUI.app
FLUTTER_CREATE_MACOS := flutter create --empty --platforms=macos --project-name gui_for_cli_flutter .
FLUTTER_CLEAN_GENERATED := rm -f README.md analysis_options.yaml *.iml test/widget_test.dart
FLUTTER_DISABLE_SANDBOX := /usr/libexec/PlistBuddy -c 'Set :com.apple.security.app-sandbox false' macos/Runner/DebugProfile.entitlements && /usr/libexec/PlistBuddy -c 'Set :com.apple.security.app-sandbox false' macos/Runner/Release.entitlements
FLUTTER_CONFIGURE_WINDOW := python3 ../../scripts/configure-flutter-macos-window.py macos/Runner/MainFlutterWindow.swift --width "$(FLUTTER_WINDOW_WIDTH)" --height "$(FLUTTER_WINDOW_HEIGHT)"
SLINT_EXE := Apps/Slint/target/release/gui-for-cli-slint
RAYGUI_EXE := Apps/Raygui/target/release/gui-for-cli-raygui
FLUTTER_APP := Apps/Flutter/build/macos/Build/Products/Release/gui_for_cli_flutter.app

DEFAULT_BUNDLE ?= Examples/WGSExtract
BUNDLE_ROOT := $(abspath $(or $(BUNDLE),$(DEFAULT_BUNDLE)))
WEB_PORT := $(or $(PORT),8787)
BENCHMARK_SAMPLES := $(or $(SAMPLES),7)

# Windows-specific tasks belong in make.ps1; this POSIX Makefile is for Unix-like shells.
.PHONY: \
	help \
	setup-dev setup-webui project \
	precheck lint lint-locales validate-bundles format \
	test test-webui test-flutter test-slint test-raygui ax-smoke ax-smoke-ios ax-all \
	build-cli run-cli \
	web web-dev tui web-icons web-kill \
	nodegui nodegui-smoke \
	build-webview-shell run-webview-shell build-webui-tauri run-webui-tauri build-webui-dioxus run-webui-dioxus \
	build-slint run-slint build-raygui run-raygui flutter flutter-build launch-flutter-slint \
	build-webui-release build-swift-release build-appkit-release build-webview-release build-tauri-release build-dioxus-release build-electron-release build-gio-release build-slint-release build-raygui-release build-flutter-release build-release-all build-release-all-prototypes \
	measure-startup-sequential benchmark-flutter benchmark-flutter-macos benchmark-gio-macos benchmark-slint benchmark-raygui \
	build-macos mac build-macos-appkit appkit build-objc-appkit objc-appkit \
	build-ios-sim build-ios-device ios ios-device \
	cloc clean \
	ci ci-fast

##@ General

help: ## Show available make targets.
	@awk 'BEGIN {FS = ":.*## "; bold = sprintf("%c[1m", 27); section = sprintf("%c[1;35m", 27); cyan = sprintf("%c[36m", 27); reset = sprintf("%c[0m", 27); printf "%sAvailable targets:%s\n", bold, reset} /^##@ / {printf "%s%s%s\n", section, substr($$0, 5), reset; next} /^[a-zA-Z0-9_-]+:.*## / {printf "  %s%-26s%s %s\n", cyan, $$1, reset, $$2}' $(MAKEFILE_LIST)

##@ Setup

setup-dev: setup-webui ## Resolve dependencies, install Tuist, and register local dev hooks.
	swift package resolve
	./scripts/tuist.sh install
	python3 scripts/dev-register.py
	python3 scripts/setup-hooks.py

setup-webui: ## Install WebUI npm dependencies.
	npm --prefix WebUI install

project: ## Generate the Xcode project/workspace with Tuist.
	./scripts/tuist.sh generate --no-open

##@ Quality

precheck: ## Run repository precheck diagnostics.
	swift run gui-for-cli precheck

lint: ## Lint Swift source formatting.
	swift format lint --recursive Sources Tests Apps scripts Project.swift Tuist.swift

lint-locales: ## Lint bundle localization TOML files (pass STRICT=1 to fail on warnings).
	python3 scripts/lint-locales.py $(if $(STRICT),--strict,)

validate-bundles: ## Run bundle manifest + locale validation across Examples/* (STRICT=1 fails on warnings).
	@swift run gui-for-cli bundle validate $(if $(STRICT),--strict,) Examples/*

format: ## Format Swift source files in place.
	swift format format --in-place --recursive Sources Tests Apps scripts Project.swift Tuist.swift

##@ Testing

ax-smoke: ## Probe the running macOS dev app via Accessibility APIs (requires pyobjc + a11y permission).
	@python3 scripts/ax-smoke.py

ax-smoke-ios: ## Probe a booted iOS Simulator via the `axe` CLI (brew install cameroncooke/axe/axe).
	@python3 scripts/ax-smoke-ios.py

ax-all: ax-smoke ax-smoke-ios ## Run both macOS and iOS accessibility smoke tests.

test: ## Run the Swift test suite.
	swift test --parallel

test-webui: ## Build and run the Web UI TypeScript tests.
	npm --prefix WebUI test

test-flutter: ## Run the Flutter renderer tests.
	cd Apps/Flutter && flutter test

test-slint: ## Run the Rust Slint renderer tests.
	cargo test --manifest-path Apps/Slint/Cargo.toml

test-raygui: ## Run the Rust Raygui renderer tests.
	cargo test --manifest-path Apps/Raygui/Cargo.toml

##@ CLI

build-cli: ## Build the CLI in release mode.
	swift build -c release

run-cli: ## Run the GUI-for-CLI command runner.
	swift run gui-for-cli run

##@ Web

web: ## Build and run the local Web UI for a bundle (set BUNDLE=Examples/WGSExtract PORT=8787).
	npm --prefix WebUI run build
	node WebUI/dist/server/main.js --bundle "$(BUNDLE_ROOT)" --port "$(WEB_PORT)"

web-dev: ## Run the Web UI with TypeScript watch, server restart, and browser reload.
	npm --prefix WebUI run dev -- --bundle "$(BUNDLE_ROOT)" --port "$(WEB_PORT)"

tui: ## Run the TypeScript terminal UI for a bundle (set BUNDLE=Examples/WGSExtract).
	npm --prefix WebUI run tui -- --bundle "$(BUNDLE_ROOT)"

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

##@ NodeGui

nodegui: ## Run the NodeGui/Qt WebUI shell for a bundle (set BUNDLE=Examples/WGSExtract).
	npm --prefix WebUI run nodegui -- --bundle "$(BUNDLE_ROOT)"

nodegui-smoke: ## Load the NodeGui shared model without opening a window.
	npm --prefix WebUI run nodegui:smoke -- --bundle "$(BUNDLE_ROOT)"

##@ Native Web Shells

build-webview-shell: ## Build the native WKWebView Web UI shell app.
	npm --prefix WebUI run build
	rm -rf "$(WEBVIEW_SHELL_APP)"
	mkdir -p "$(WEBVIEW_SHELL_APP)/Contents/MacOS" "$(WEBVIEW_SHELL_APP)/Contents/Resources"
	cp Apps/WebViewShell/Info.plist "$(WEBVIEW_SHELL_APP)/Contents/Info.plist"
	swiftc -O -framework AppKit -framework WebKit Apps/WebViewShell/Shell.swift -o "$(WEBVIEW_SHELL_EXE)"

run-webview-shell: build-webview-shell ## Run the native WKWebView Web UI shell against the source tree.
	GFC_REPO_ROOT="$(abspath .)" GFC_NODE_PATH="$$(command -v node)" "$(WEBVIEW_SHELL_EXE)"

build-webui-tauri: ## Build the Tauri Web UI shell app.
	npm --prefix WebUI run tauri:build

run-webui-tauri: ## Run the Tauri Web UI shell in development mode.
	npm --prefix WebUI run tauri:dev

build-webui-dioxus: ## Build the Dioxus Native Web UI shell app.
	npm --prefix WebUI run build
	cargo build --release --manifest-path "$(RUST_APPS_DIR)/Cargo.toml"

run-webui-dioxus: ## Run the Dioxus Native Web UI shell against the source tree.
	npm --prefix WebUI run build
	GFC_REPO_ROOT="$(abspath .)" GFC_NODE_PATH="$$(command -v node)" cargo run --release --manifest-path "$(RUST_APPS_DIR)/Cargo.toml"

##@ Prototype Renderers

build-slint: ## Build the Rust Slint desktop app in release mode.
	cargo build --manifest-path Apps/Slint/Cargo.toml --release

run-slint: build-slint ## Run the Rust Slint desktop app (set BUNDLE=Examples/WGSExtract).
	"$(SLINT_EXE)" --bundle "$(BUNDLE_ROOT)"

build-raygui: ## Build the Rust Raygui desktop app in release mode.
	cargo build --manifest-path Apps/Raygui/Cargo.toml --release

run-raygui: build-raygui ## Run the Rust Raygui desktop app (set BUNDLE=Examples/WGSExtract).
	"$(RAYGUI_EXE)" --bundle "$(BUNDLE_ROOT)"

flutter: ## Run the Flutter desktop app against Examples/WGSExtract.
	cd Apps/Flutter && $(FLUTTER_CREATE_MACOS) && $(FLUTTER_DISABLE_SANDBOX) && $(FLUTTER_CONFIGURE_WINDOW) && $(FLUTTER_CLEAN_GENERATED) && flutter run -d macos --dart-define=GFC_REPO_ROOT="$(abspath .)" --dart-define=GFC_BUNDLE_ROOT="$(BUNDLE_ROOT)"

flutter-build: ## Build the Flutter desktop app for macOS.
	cd Apps/Flutter && $(FLUTTER_CREATE_MACOS) && $(FLUTTER_DISABLE_SANDBOX) && $(FLUTTER_CONFIGURE_WINDOW) && $(FLUTTER_CLEAN_GENERATED) && flutter build macos --release --dart-define=GFC_REPO_ROOT="$(abspath .)" --dart-define=GFC_BUNDLE_ROOT="$(BUNDLE_ROOT)"

launch-flutter-slint: ## Launch built Flutter, Slint, and SwiftUI apps for visual startup comparison.
	scripts/launch-flutter-slint.sh $(LAUNCH_ARGS)

##@ Release Packages

build-webui-release: ## Build a standalone Web UI release folder with bundled Node.
	npm --prefix WebUI run build
	npm --prefix WebUI run tauri:prepare-node
	rm -rf "$(WEBUI_RELEASE_DIR)"
	mkdir -p "$(WEBUI_RELEASE_DIR)/WebUI" "$(WEBUI_RELEASE_DIR)/Examples"
	ditto WebUI/dist "$(WEBUI_RELEASE_DIR)/WebUI/dist"
	ditto WebUI/vendor "$(WEBUI_RELEASE_DIR)/WebUI/vendor"
	cp WebUI/index.html WebUI/styles.css "$(WEBUI_RELEASE_DIR)/WebUI/"
	ditto WebUI/src-tauri/resources/node "$(WEBUI_RELEASE_DIR)/node"
	ditto Examples/WGSExtract "$(WEBUI_RELEASE_DIR)/Examples/WGSExtract"
	printf '%s\n' '#!/usr/bin/env sh' 'set -eu' 'cd "$$(dirname "$$0")"' 'exec ./node/bin/node WebUI/dist/server/main.js --bundle "$$(pwd)/Examples/WGSExtract" "$$@"' > "$(WEBUI_RELEASE_DIR)/run-webui.sh"
	chmod +x "$(WEBUI_RELEASE_DIR)/run-webui.sh"

build-swift-release: project ## Build and stage the release SwiftUI macOS app.
	xcodebuild -workspace GUIForCLI.xcworkspace -scheme GUIForCLIMac -configuration Release -derivedDataPath "$(DERIVED_DATA_PATH)" -destination '$(MACOS_DESTINATION)' build CODE_SIGNING_ALLOWED=NO
	rm -rf "$(SWIFT_RELEASE_DIR)"
	mkdir -p "$(SWIFT_RELEASE_DIR)"
	ditto "$(MACOS_RELEASE_APP)" "$(SWIFT_RELEASE_DIR)/$(APP_NAME).app"

build-appkit-release: project ## Build and stage the release AppKit macOS app.
	xcodebuild -workspace GUIForCLI.xcworkspace -scheme GUIForCLIAppKit -configuration Release -derivedDataPath "$(DERIVED_DATA_PATH)" -destination '$(MACOS_DESTINATION)' build CODE_SIGNING_ALLOWED=NO
	rm -rf "$(APPKIT_RELEASE_DIR)"
	mkdir -p "$(APPKIT_RELEASE_DIR)"
	ditto "$(MACOS_APPKIT_RELEASE_APP)" "$(APPKIT_RELEASE_DIR)/$(APPKIT_APP_NAME).app"

build-webview-release: ## Build and stage the standalone native WKWebView Web UI shell app.
	npm --prefix WebUI run build
	npm --prefix WebUI run tauri:prepare-node
	rm -rf "$(WEBVIEW_RELEASE_DIR)"
	mkdir -p "$(WEBVIEW_RELEASE_DIR)/GUI for CLI WebView Shell.app/Contents/MacOS" "$(WEBVIEW_RELEASE_DIR)/GUI for CLI WebView Shell.app/Contents/Resources/WebUI" "$(WEBVIEW_RELEASE_DIR)/GUI for CLI WebView Shell.app/Contents/Resources/Examples"
	cp Apps/WebViewShell/Info.plist "$(WEBVIEW_RELEASE_DIR)/GUI for CLI WebView Shell.app/Contents/Info.plist"
	swiftc -O -framework AppKit -framework WebKit Apps/WebViewShell/Shell.swift -o "$(WEBVIEW_RELEASE_DIR)/GUI for CLI WebView Shell.app/Contents/MacOS/GUIForCLIWebViewShell"
	ditto WebUI/dist "$(WEBVIEW_RELEASE_DIR)/GUI for CLI WebView Shell.app/Contents/Resources/WebUI/dist"
	ditto WebUI/vendor "$(WEBVIEW_RELEASE_DIR)/GUI for CLI WebView Shell.app/Contents/Resources/WebUI/vendor"
	cp WebUI/index.html WebUI/styles.css "$(WEBVIEW_RELEASE_DIR)/GUI for CLI WebView Shell.app/Contents/Resources/WebUI/"
	ditto WebUI/src-tauri/resources/node "$(WEBVIEW_RELEASE_DIR)/GUI for CLI WebView Shell.app/Contents/Resources/node"
	ditto Examples/WGSExtract "$(WEBVIEW_RELEASE_DIR)/GUI for CLI WebView Shell.app/Contents/Resources/Examples/WGSExtract"

build-tauri-release: ## Build and stage the standalone Tauri Web UI shell app.
	npm --prefix WebUI run tauri:build
	rm -rf "$(TAURI_RELEASE_DIR)"
	mkdir -p "$(TAURI_RELEASE_DIR)"
	ditto "$(WEBUI_TAURI_APP)" "$(TAURI_RELEASE_DIR)/GUI for CLI WebUI.app"

build-dioxus-release: build-webui-dioxus ## Build and stage the standalone Dioxus Native Web UI shell app.
	npm --prefix WebUI run tauri:prepare-node
	rm -rf "$(DIOXUS_RELEASE_DIR)"
	mkdir -p "$(DIOXUS_RELEASE_DIR)/WebUI" "$(DIOXUS_RELEASE_DIR)/Examples" "$(DIOXUS_RELEASE_DIR)/Sources/GUIForCLICore/Resources"
	cp "$(RUST_APP_EXE)" "$(DIOXUS_RELEASE_DIR)/gui-for-cli-webui-dioxus"
	chmod +x "$(DIOXUS_RELEASE_DIR)/gui-for-cli-webui-dioxus"
	ditto WebUI/dist "$(DIOXUS_RELEASE_DIR)/WebUI/dist"
	ditto WebUI/vendor "$(DIOXUS_RELEASE_DIR)/WebUI/vendor"
	cp WebUI/index.html WebUI/styles.css "$(DIOXUS_RELEASE_DIR)/WebUI/"
	ditto WebUI/src-tauri/resources/node "$(DIOXUS_RELEASE_DIR)/node"
	ditto Examples/WGSExtract "$(DIOXUS_RELEASE_DIR)/Examples/WGSExtract"
	ditto Sources/GUIForCLICore/Resources/BuiltinStrings "$(DIOXUS_RELEASE_DIR)/Sources/GUIForCLICore/Resources/BuiltinStrings"

build-electron-release: ## Build and stage the standalone Electron Web UI shell app.
	npm --prefix WebUI run electron:package -- --out "$(abspath $(ELECTRON_RELEASE_DIR))"

build-gio-release: ## Build and stage the standalone Go Gio app.
	rm -rf "$(GIO_RELEASE_DIR)"
	mkdir -p "$(GIO_RELEASE_DIR)/Examples" "$(GIO_RELEASE_DIR)/Resources"
	cd Apps/Gio && $(GIO_GO) build -trimpath -ldflags='-s -w' -o "../../$(GIO_RELEASE_DIR)/gui-for-cli-gio" .
	ditto Examples/WGSExtract "$(GIO_RELEASE_DIR)/Examples/WGSExtract"
	ditto Sources/GUIForCLICore/Resources/BuiltinStrings "$(GIO_RELEASE_DIR)/Resources/BuiltinStrings"

build-slint-release: build-slint ## Build and stage the Rust Slint desktop app.
	rm -rf "$(SLINT_RELEASE_DIR)"
	mkdir -p "$(SLINT_RELEASE_DIR)/Examples"
	cp "$(SLINT_EXE)" "$(SLINT_RELEASE_DIR)/gui-for-cli-slint"
	ditto Examples/WGSExtract "$(SLINT_RELEASE_DIR)/Examples/WGSExtract"

build-raygui-release: build-raygui ## Build and stage the Rust Raygui desktop app.
	rm -rf "$(RAYGUI_RELEASE_DIR)"
	mkdir -p "$(RAYGUI_RELEASE_DIR)/Examples"
	cp "$(RAYGUI_EXE)" "$(RAYGUI_RELEASE_DIR)/gui-for-cli-raygui"
	ditto Examples/WGSExtract "$(RAYGUI_RELEASE_DIR)/Examples/WGSExtract"

build-flutter-release: flutter-build ## Build and stage the Flutter macOS desktop app.
	rm -rf "$(FLUTTER_RELEASE_DIR)"
	mkdir -p "$(FLUTTER_RELEASE_DIR)"
	ditto "$(FLUTTER_APP)" "$(FLUTTER_RELEASE_DIR)/GUI for CLI Flutter.app"

build-release-all: build-webui-release build-swift-release build-appkit-release build-webview-release build-tauri-release build-dioxus-release build-electron-release build-gio-release ## Build core release GUI options available in this checkout.

build-release-all-prototypes: build-release-all build-slint-release build-raygui-release build-flutter-release ## Include external worktree prototype releases.

##@ Benchmarks

measure-startup-sequential: ## Launch each GUI app sequentially for 2s, kill it, then continue.
	scripts/measure-startup-sequential.sh $(LAUNCH_ARGS)

benchmark-gio-macos: build-gio-release ## Benchmark the staged Gio app startup on macOS (set SAMPLES=7).
	python3 scripts/benchmark-gio-macos.py --samples "$(BENCHMARK_SAMPLES)" --output "$(GIO_RELEASE_DIR)/benchmark-macos.json" "$(GIO_RELEASE_DIR)/gui-for-cli-gio"

benchmark-flutter: ## Run the Flutter app benchmark script (PowerShell, Windows desktop target).
	pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/benchmark-flutter.ps1

benchmark-flutter-macos: ## Benchmark the Flutter macOS desktop target.
	cd Apps/Flutter && $(FLUTTER_CREATE_MACOS) && $(FLUTTER_DISABLE_SANDBOX) && $(FLUTTER_CONFIGURE_WINDOW) && $(FLUTTER_CLEAN_GENERATED) && flutter build macos --release --dart-define=GFC_REPO_ROOT="$(abspath .)" --dart-define=GFC_BUNDLE_ROOT="$(BUNDLE_ROOT)" --dart-define=GFC_BENCHMARK_OUTPUT="$(FLUTTER_BENCHMARK_OUTPUT)"
	python3 scripts/benchmark-flutter-macos.py Apps/Flutter/build/macos/Build/Products/Release/gui_for_cli_flutter.app --marker "$(FLUTTER_BENCHMARK_OUTPUT)"

benchmark-slint: build-slint ## Benchmark the Rust Slint desktop app with the full WGSExtract bundle.
	GUI_FOR_CLI_OFFLINE=1 "$(SLINT_EXE)" --bundle "$(BUNDLE_ROOT)" --benchmark --benchmark-full --once

benchmark-raygui: build-raygui ## Benchmark the Rust Raygui desktop app to first rendered frame.
	GUI_FOR_CLI_OFFLINE=1 "$(RAYGUI_EXE)" --bundle "$(BUNDLE_ROOT)" --benchmark --once

##@ macOS

build-macos: project ## Build the macOS desktop app.
	xcodebuild -workspace GUIForCLI.xcworkspace -scheme GUIForCLIMac -configuration Debug -derivedDataPath "$(DERIVED_DATA_PATH)" -destination '$(MACOS_DESTINATION)' build CODE_SIGNING_ALLOWED=NO

mac: build-macos ## Build and run the macOS desktop app.
	open "$(MACOS_APP)"

build-macos-appkit: project ## Build the AppKit macOS desktop app.
	xcodebuild -workspace GUIForCLI.xcworkspace -scheme GUIForCLIAppKit -configuration Debug -derivedDataPath "$(DERIVED_DATA_PATH)" -destination '$(MACOS_DESTINATION)' build CODE_SIGNING_ALLOWED=NO

appkit: build-macos-appkit ## Build and run the AppKit macOS desktop app.
	open "$(MACOS_APPKIT_APP)"

build-objc-appkit: project ## Build the Objective-C AppKit Test desktop app.
	xcodebuild -workspace GUIForCLI.xcworkspace -scheme GUIForCLIObjCAppKit -configuration Debug -derivedDataPath "$(DERIVED_DATA_PATH)" -destination '$(MACOS_DESTINATION)' build CODE_SIGNING_ALLOWED=NO

objc-appkit: build-objc-appkit ## Build and run the Objective-C AppKit Test desktop app.
	GFC_REPO_ROOT="$(abspath .)" GFC_BUNDLE_PATH="$(BUNDLE_ROOT)" "$(OBJC_APPKIT_EXE)"

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
	rm -rf Apps/Raygui/target
	rm -rf out/* tmp/*

cloc: ## Count lines of code, excluding gitignored files.
	@command -v cloc >/dev/null 2>&1 || (echo "cloc not found. Install with: brew install cloc" >&2; exit 1)
	cloc --vcs=git .

##@ CI

ci: ## Run the full CI pipeline locally (mirrors .github/workflows/ci.yml).
	python3 scripts/ci-local.py

ci-fast: ## Run the CI pipeline locally, skipping the iOS build.
	python3 scripts/ci-local.py --fast
