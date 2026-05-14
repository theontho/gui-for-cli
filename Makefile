.DEFAULT_GOAL := help

APP_NAME ?= GUI for CLI
APPKIT_APP_NAME ?= swift appkit test
OBJC_APPKIT_APP_NAME ?= GUI for CLI ObjC AppKit Test
APPLE_DIR := platform/apple
APPLE_WORKSPACE := $(APPLE_DIR)/GUIForCLI.xcworkspace
APPLE_PROJECT := $(APPLE_DIR)/GUIForCLI.xcodeproj
SWIFT_GIT_ENV := GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all
DERIVED_DATA_PATH ?= $(APPLE_DIR)/DerivedData
RELEASE_DIR ?= out/release
IOS_BUNDLE_ID ?= dev.guiforcli.gui-for-cli.ios
IOS_SIMULATOR ?= booted
IOS_IPAD_SIMULATOR ?= booted
IOS_SIM_DESTINATION ?= generic/platform=iOS Simulator
IOS_DEVICE_DESTINATION ?= generic/platform=iOS
MACOS_DESTINATION ?= platform=macOS
IOS_CORE_RESOURCE_BUNDLE ?= GUIForCLIShared_GUIForCLICore.bundle

MACOS_APP := $(DERIVED_DATA_PATH)/Build/Products/Debug/$(APP_NAME).app
MACOS_APPKIT_APP := $(DERIVED_DATA_PATH)/Build/Products/Debug/$(APPKIT_APP_NAME).app
MACOS_RELEASE_APP := $(DERIVED_DATA_PATH)/Build/Products/Release/$(APP_NAME).app
MACOS_APPKIT_RELEASE_APP := $(DERIVED_DATA_PATH)/Build/Products/Release/$(APPKIT_APP_NAME).app
OBJC_APPKIT_APP := $(DERIVED_DATA_PATH)/Build/Products/Debug/$(OBJC_APPKIT_APP_NAME).app
OBJC_APPKIT_EXE := $(OBJC_APPKIT_APP)/Contents/MacOS/$(OBJC_APPKIT_APP_NAME)
IOS_SIM_APP := $(DERIVED_DATA_PATH)/Build/Products/Debug-iphonesimulator/$(APP_NAME).app
IOS_DEVICE_APP := $(DERIVED_DATA_PATH)/Build/Products/Debug-iphoneos/$(APP_NAME).app
IOS_SIM_DEMO_BUNDLE := $(IOS_SIM_APP)/$(IOS_CORE_RESOURCE_BUNDLE)/Resources/DemoBundles/WGSExtract
IOS_DEVICE_DEMO_BUNDLE := $(IOS_DEVICE_APP)/$(IOS_CORE_RESOURCE_BUNDLE)/Resources/DemoBundles/WGSExtract
WEBUI_RELEASE_DIR := $(RELEASE_DIR)/webui
SWIFT_RELEASE_DIR := $(RELEASE_DIR)/swift
APPKIT_RELEASE_DIR := $(RELEASE_DIR)/appkit
WEBVIEW_RELEASE_DIR := $(RELEASE_DIR)/webview
TAURI_RELEASE_DIR := $(RELEASE_DIR)/tauri
ELECTRON_RELEASE_DIR := $(RELEASE_DIR)/electron
DIOXUS_RELEASE_DIR := $(RELEASE_DIR)/dioxus
RUST_APPS_DIR := exp-platform/rust/dioxus-shell
RUST_APP_EXE := $(RUST_APPS_DIR)/target/release/gui-for-cli-webui-dioxus
GTK4_RELEASE_DIR := $(RELEASE_DIR)/gtk4
GTK4_EXE := exp-platform/rust/gtk4/target/release/gui-for-cli-gtk4
SLINT_RELEASE_DIR := $(RELEASE_DIR)/slint
RAYGUI_RELEASE_DIR := $(RELEASE_DIR)/raygui
RAYGUI_C_RELEASE_DIR := $(RELEASE_DIR)/raygui-c
IMGUI_RELEASE_DIR := $(RELEASE_DIR)/imgui
ICED_RELEASE_DIR := $(RELEASE_DIR)/iced
MAKEPAD_RELEASE_DIR := $(RELEASE_DIR)/makepad
EGUI_RELEASE_DIR := $(RELEASE_DIR)/egui
IMGUI_CPP_RELEASE_DIR := $(RELEASE_DIR)/imgui-cpp
QT_QML_RELEASE_DIR := $(RELEASE_DIR)/qt-qml
RAYGUI_C_BUILD_DIR := exp-platform/c/raygui/build
IMGUI_CPP_BUILD_DIR := exp-platform/cpp/imgui-cpp/build
QT_QML_BUILD_DIR := exp-platform/cpp/qt-qml/build
QT_QML_VALIDATE_BUILD_DIR := exp-platform/cpp/qt-qml/build-validate
FLUTTER_RELEASE_DIR := $(RELEASE_DIR)/flutter
GIO_RELEASE_DIR := $(RELEASE_DIR)/gio
AVALONIA_RELEASE_DIR := $(RELEASE_DIR)/avalonia
AVALONIA_DIR := exp-platform/dotnet/avalonia
AVALONIA_APP_PROJECT := $(AVALONIA_DIR)/GUIForCLIAvalonia/GUIForCLIAvalonia.csproj
AVALONIA_TEST_PROJECT := $(AVALONIA_DIR)/GUIForCLIAvalonia.Tests/GUIForCLIAvalonia.Tests.csproj
FYNE_RELEASE_DIR := $(RELEASE_DIR)/fyne
FLUTTER_BENCHMARK_OUTPUT ?= /tmp/gui-for-cli-flutter-benchmark.txt
FLUTTER_WINDOW_WIDTH ?= 1344
FLUTTER_WINDOW_HEIGHT ?= 864
GIO_GO ?= GOTOOLCHAIN=go1.25.0 go
FYNE_GO ?= GOTOOLCHAIN=go1.25.0 go
PYTHON_TOGA_DIR := exp-platform/python/toga
PYTHON_TOGA_SRC := $(PYTHON_TOGA_DIR)/src
PYTHON_TOGA_ENV := PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$(abspath $(PYTHON_TOGA_SRC))"
PYTHON_TOGA_WORKSPACE ?= tmp/python-toga-workspace
PYTHON_TOGA_BENCHMARK_OUTPUT ?= out/python-toga/benchmark.txt
WEBVIEW_SHELL_APP := $(DERIVED_DATA_PATH)/WebViewShell/GUI for CLI WebView Shell.app
WEBVIEW_SHELL_EXE := $(WEBVIEW_SHELL_APP)/Contents/MacOS/GUIForCLIWebViewShell
WEBUI_TAURI_APP := platform/typescript/web/packagers/tauri/target/release/bundle/macos/GUI for CLI WebUI.app
FLUTTER_CREATE_MACOS := flutter create --empty --platforms=macos --project-name gui_for_cli_flutter .
FLUTTER_CLEAN_GENERATED := rm -f README.md analysis_options.yaml *.iml test/widget_test.dart
FLUTTER_DISABLE_SANDBOX := /usr/libexec/PlistBuddy -c 'Set :com.apple.security.app-sandbox false' macos/Runner/DebugProfile.entitlements && /usr/libexec/PlistBuddy -c 'Set :com.apple.security.app-sandbox false' macos/Runner/Release.entitlements
FLUTTER_CONFIGURE_WINDOW := python3 ../../../scripts/configure-flutter-macos-window.py macos/Runner/MainFlutterWindow.swift --width "$(FLUTTER_WINDOW_WIDTH)" --height "$(FLUTTER_WINDOW_HEIGHT)"
SLINT_EXE := exp-platform/rust/slint/target/release/gui-for-cli-slint
RAYGUI_EXE := exp-platform/rust/raygui/target/release/gui-for-cli-raygui
RAYGUI_C_EXE := $(RAYGUI_C_BUILD_DIR)/gui-for-cli-raygui-c
IMGUI_EXE := exp-platform/rust/imgui/target/release/gui-for-cli-imgui
ICED_EXE := exp-platform/rust/iced/target/release/gui-for-cli-iced
MAKEPAD_EXE := exp-platform/rust/makepad/target/release/gui-for-cli-makepad
EGUI_EXE := exp-platform/rust/egui/target/release/gui-for-cli-egui
IMGUI_CPP_EXE := $(IMGUI_CPP_BUILD_DIR)/gui-for-cli-imgui-cpp
QT_QML_EXE := $(QT_QML_BUILD_DIR)/gui-for-cli-qt-qml
FLUTTER_APP := exp-platform/dart/flutter/build/macos/Build/Products/Release/gui_for_cli_flutter.app
KOTLIN_COMPOSE_DIR := exp-platform/kotlin/compose
KOTLIN_GRADLE ?= gradle
KOTLIN_GRADLE_FLAGS ?= --console=plain --quiet
KOTLIN_JAVA_HOME ?= $(if $(wildcard /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home),/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home)
KOTLIN_ANDROID_HOME ?= $(if $(wildcard $(HOME)/Library/Android/sdk),$(HOME)/Library/Android/sdk)
KOTLIN_ENV := $(strip $(if $(KOTLIN_JAVA_HOME),JAVA_HOME="$(KOTLIN_JAVA_HOME)") $(if $(KOTLIN_ANDROID_HOME),ANDROID_HOME="$(KOTLIN_ANDROID_HOME)" ANDROID_SDK_ROOT="$(KOTLIN_ANDROID_HOME)"))

DEFAULT_BUNDLE ?= examples/WGSExtract
BUNDLE_ROOT := $(abspath $(or $(BUNDLE),$(DEFAULT_BUNDLE)))
WEB_PORT := $(or $(PORT),8787)
BENCHMARK_SAMPLES := $(or $(SAMPLES),7)
SWIFT_FORMAT_PATHS := \
	$(APPLE_DIR)/Package.swift \
	$(APPLE_DIR)/Project.swift \
	$(APPLE_DIR)/Tuist.swift \
	$(APPLE_DIR)/shared/Package.swift \
	$(APPLE_DIR)/shared/Sources \
	$(APPLE_DIR)/shared/Tests \
	$(APPLE_DIR)/shared/app \
	$(APPLE_DIR)/swiftui \
	$(APPLE_DIR)/exp \
	scripts

# Windows-specific tasks belong in make.ps1; this POSIX Makefile is for Unix-like shells.
.PHONY: \
	help \
	setup-dev setup-webui project \
	precheck lint lint-locales validate-bundles format \
	test test-webui test-toga test-flutter test-compose test-android test-gtk4 test-slint test-raygui test-imgui test-iced test-makepad test-egui test-qt-qml test-avalonia test-fyne ax-smoke ax-smoke-ios ax-all \
	build-cli run-cli \
	web web-dev tui web-icons web-kill \
	nodegui nodegui-smoke \
	run-toga toga \
	build-webview-shell run-webview-shell build-webui-tauri run-webui-tauri build-webui-dioxus run-webui-dioxus \
	build-gtk4 run-gtk4 build-slint run-slint build-raygui run-raygui build-raygui-c run-raygui-c build-imgui run-imgui build-iced run-iced build-makepad run-makepad build-egui run-egui build-imgui-cpp run-imgui-cpp build-qt-qml run-qt-qml build-fyne run-fyne flutter flutter-build build-android run-compose-desktop build-compose-desktop launch-flutter-slint \
	restore-avalonia build-avalonia run-avalonia \
	build-webui-release build-swift-release build-appkit-release build-webview-release build-tauri-release build-dioxus-release build-electron-release build-gio-release build-gtk4-release build-slint-release build-raygui-release build-raygui-c-release build-imgui-release build-iced-release build-makepad-release build-egui-release build-imgui-cpp-release build-qt-qml-release build-fyne-release build-avalonia-release build-flutter-release build-release-all build-release-all-prototypes \
	measure-startup-sequential benchmark-toga benchmark-flutter benchmark-flutter-macos benchmark-gio-macos benchmark-fyne-macos benchmark-gtk4 benchmark-slint benchmark-raygui benchmark-raygui-c benchmark-imgui benchmark-iced benchmark-makepad benchmark-egui benchmark-imgui-cpp benchmark-qt-qml benchmark-avalonia \
	build-macos mac build-macos-appkit appkit build-objc-appkit objc-appkit \
	build-ios-sim build-ios-device ios ios-ipad-sim ios-device \
	cloc clean \
	ci ci-fast

##@ General

help: ## Show available make targets.
	@awk 'BEGIN {FS = ":.*## "; bold = sprintf("%c[1m", 27); section = sprintf("%c[1;35m", 27); cyan = sprintf("%c[36m", 27); reset = sprintf("%c[0m", 27); printf "%sAvailable targets:%s\n", bold, reset} /^##@ / {printf "%s%s%s\n", section, substr($$0, 5), reset; next} /^[a-zA-Z0-9_-]+:.*## / {printf "  %s%-26s%s %s\n", cyan, $$1, reset, $$2}' $(MAKEFILE_LIST)

##@ Setup

setup-dev: setup-webui ## Resolve dependencies, install Tuist, and register local dev hooks.
	$(SWIFT_GIT_ENV) swift package --package-path "$(APPLE_DIR)" resolve
	cd "$(APPLE_DIR)" && ../../scripts/tuist.sh install
	python3 scripts/dev-register.py
	python3 scripts/setup-hooks.py

setup-webui: ## Install WebUI npm dependencies.
	npm --prefix platform/typescript install

project: ## Generate the Xcode project/workspace with Tuist.
	cd "$(APPLE_DIR)" && ../../scripts/tuist.sh generate --no-open

##@ Quality

precheck: ## Run repository precheck diagnostics.
	$(SWIFT_GIT_ENV) swift run --package-path "$(APPLE_DIR)" gui-for-cli precheck

lint: ## Lint Swift source formatting.
	swift format lint --recursive $(SWIFT_FORMAT_PATHS)

lint-locales: ## Lint bundle localization TOML files (pass STRICT=1 to fail on warnings).
	python3 scripts/lint-locales.py $(if $(STRICT),--strict,)

validate-bundles: ## Run bundle manifest + locale validation across examples/* (STRICT=1 fails on warnings).
	@$(SWIFT_GIT_ENV) swift run --package-path "$(APPLE_DIR)" gui-for-cli bundle validate $(if $(STRICT),--strict,) examples/*

format: ## Format Swift source files in place.
	swift format format --in-place --recursive $(SWIFT_FORMAT_PATHS)

##@ Stable Apple Platform

ax-smoke: build-macos ## Probe the macOS dev app via Accessibility APIs (requires pyobjc + a11y permission).
	@set -eu; \
	mkdir -p tmp/ax-smoke; \
	log="tmp/ax-smoke/macos-app.log"; \
	"$(MACOS_APP)/Contents/MacOS/$(APP_NAME)" >"$$log" 2>&1 & \
	pid=$$!; \
	trap 'kill '"$$pid"' 2>/dev/null || true; wait '"$$pid"' 2>/dev/null || true' EXIT; \
	sleep 3; \
	python3 scripts/ax-smoke.py --pid "$$pid"

##@ Experimental Apple Platform

ax-smoke-ios: ios ## Probe a booted iOS Simulator via the `axe` CLI (brew install cameroncooke/axe/axe).
	@python3 scripts/ax-smoke-ios.py

ax-all: ax-smoke ax-smoke-ios ## Run both macOS and iOS accessibility smoke tests.

##@ Stable Apple Platform

test: ## Run the Swift test suite.
	$(SWIFT_GIT_ENV) swift test --package-path "$(APPLE_DIR)" --parallel

##@ Stable TypeScript Platform

test-webui: ## Build and run the Web UI TypeScript tests.
	npm --prefix platform/typescript test

##@ Experimental Dart Platform

test-flutter: ## Run the Flutter renderer tests.
	cd exp-platform/dart/flutter && flutter test

##@ Experimental Kotlin Platform

test-compose: ## Run shared JVM tests for the Compose Kotlin experiment.
	cd "$(KOTLIN_COMPOSE_DIR)" && $(KOTLIN_ENV) $(KOTLIN_GRADLE) $(KOTLIN_GRADLE_FLAGS) :shared:test

test-android: ## Run JVM unit tests for the experimental Android Compose app.
	cd "$(KOTLIN_COMPOSE_DIR)" && $(KOTLIN_ENV) $(KOTLIN_GRADLE) $(KOTLIN_GRADLE_FLAGS) :androidApp:testDebugUnitTest

##@ Experimental Rust Platform

test-gtk4: ## Run static checks for the Rust GTK4 renderer core.
	cargo check --manifest-path exp-platform/rust/gtk4/Cargo.toml --no-default-features

test-slint: ## Run the Rust Slint renderer tests.
	cargo test --manifest-path exp-platform/rust/slint/Cargo.toml

test-raygui: ## Run the Rust Raygui renderer tests.
	cargo test --manifest-path exp-platform/rust/raygui/Cargo.toml

test-imgui: ## Run the Rust ImGui renderer tests.
	cargo test --manifest-path exp-platform/rust/imgui/Cargo.toml

test-iced: ## Run the Rust Iced renderer tests.
	cargo test --manifest-path exp-platform/rust/iced/Cargo.toml

test-makepad: ## Run the Rust Makepad renderer tests.
	cargo test --manifest-path exp-platform/rust/makepad/Cargo.toml

test-egui: ## Run the Rust egui renderer tests.
	cargo test --manifest-path exp-platform/rust/egui/Cargo.toml

##@ Experimental C++ Platform

test-qt-qml: ## Validate the Qt 6/QML renderer source manifest without requiring Qt.
	cmake -S exp-platform/cpp/qt-qml -B "$(QT_QML_VALIDATE_BUILD_DIR)" -DGUI_FOR_CLI_QT_QML_VALIDATE_ONLY=ON
	cmake --build "$(QT_QML_VALIDATE_BUILD_DIR)" --config Release

##@ Experimental Go Platform

test-fyne: ## Run the Go Fyne renderer tests.
	cd exp-platform/go/fyne && $(FYNE_GO) test ./...

##@ Stable Apple Platform

build-cli: ## Build the CLI in release mode.
	$(SWIFT_GIT_ENV) swift build --package-path "$(APPLE_DIR)" -c release

run-cli: ## Run the GUI-for-CLI command runner.
	$(SWIFT_GIT_ENV) swift run --package-path "$(APPLE_DIR)" gui-for-cli run

##@ Stable TypeScript Platform

web: ## Build and run the local Web UI for a bundle (set BUNDLE=examples/WGSExtract PORT=8787).
	npm --prefix platform/typescript run build
	node platform/typescript/dist/web/src/server/main.js --bundle "$(BUNDLE_ROOT)" --port "$(WEB_PORT)"

web-dev: ## Run the Web UI with TypeScript watch, server restart, and browser reload.
	npm --prefix platform/typescript run dev -- --bundle "$(BUNDLE_ROOT)" --port "$(WEB_PORT)"

tui: ## Run the TypeScript terminal UI for a bundle (set BUNDLE=examples/WGSExtract).
	npm --prefix platform/typescript run tui -- --bundle "$(BUNDLE_ROOT)"

web-icons: ## Update vendored Web UI Bootstrap Icons assets from npm.
	npm --prefix platform/typescript run vendor-icons

web-kill: ## Kill all running local Web UI server instances.
	@set -eu; \
	bold="$$(printf '\033[1m')"; \
	green="$$(printf '\033[32m')"; \
	yellow="$$(printf '\033[33m')"; \
	red="$$(printf '\033[31m')"; \
	reset="$$(printf '\033[0m')"; \
	pids="$$(ps -axww -o pid=,args= | awk '$$2 ~ /(^|\/)node$$/ && $$0 ~ /platform\/typescript\/dist\/web\/src\/server\/main\.js/ { print $$1 }' | sort -u)"; \
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

##@ Experimental TypeScript Platform

nodegui: ## Run the NodeGui/Qt WebUI shell for a bundle (set BUNDLE=examples/WGSExtract).
	npm --prefix platform/typescript run nodegui -- --bundle "$(BUNDLE_ROOT)"

nodegui-smoke: ## Load the NodeGui shared model without opening a window.
	npm --prefix platform/typescript run nodegui:smoke -- --bundle "$(BUNDLE_ROOT)"

##@ Experimental Python Platform

test-toga: ## Run headless tests for the Python Toga/BeeWare renderer.
	$(PYTHON_TOGA_ENV) python3 -m unittest discover -s "$(PYTHON_TOGA_DIR)/tests"

run-toga: ## Run the experimental Python Toga/BeeWare renderer (set BUNDLE=examples/WGSExtract).
	$(PYTHON_TOGA_ENV) python3 -m gui_for_cli_toga --repo-root "$(abspath .)" --bundle "$(BUNDLE_ROOT)" --workspace-root "$(abspath $(PYTHON_TOGA_WORKSPACE))"

toga: run-toga ## Alias for run-toga.

##@ Stable TypeScript Packagers

build-webview-shell: ## Build the native WKWebView Web UI shell app.
	npm --prefix platform/typescript run build
	rm -rf "$(WEBVIEW_SHELL_APP)"
	mkdir -p "$(WEBVIEW_SHELL_APP)/Contents/MacOS" "$(WEBVIEW_SHELL_APP)/Contents/Resources"
	cp platform/typescript/web/packagers/webview-shell/Info.plist "$(WEBVIEW_SHELL_APP)/Contents/Info.plist"
	swiftc -O -framework AppKit -framework WebKit platform/typescript/web/packagers/webview-shell/Shell.swift -o "$(WEBVIEW_SHELL_EXE)"

run-webview-shell: build-webview-shell ## Run the native WKWebView Web UI shell against the source tree.
	GFC_REPO_ROOT="$(abspath .)" GFC_NODE_PATH="$$(command -v node)" "$(WEBVIEW_SHELL_EXE)"

build-webui-tauri: ## Build the Tauri Web UI shell app.
	npm --prefix platform/typescript run tauri:build

run-webui-tauri: ## Run the Tauri Web UI shell in development mode.
	npm --prefix platform/typescript run tauri:dev

##@ Experimental Rust Platform

build-webui-dioxus: ## Build the Dioxus Native Web UI shell app.
	npm --prefix platform/typescript run build
	cargo build --release --manifest-path "$(RUST_APPS_DIR)/Cargo.toml"

run-webui-dioxus: ## Run the Dioxus Native Web UI shell against the source tree.
	npm --prefix platform/typescript run build
	GFC_REPO_ROOT="$(abspath .)" GFC_NODE_PATH="$$(command -v node)" cargo run --release --manifest-path "$(RUST_APPS_DIR)/Cargo.toml"

##@ Experimental Rust Platform

build-gtk4: ## Build the Rust GTK4/libadwaita desktop app in release mode.
	cargo build --manifest-path exp-platform/rust/gtk4/Cargo.toml --features gtk-ui --release

run-gtk4: build-gtk4 ## Run the Rust GTK4/libadwaita desktop app (set BUNDLE=examples/WGSExtract).
	"$(GTK4_EXE)" --bundle "$(BUNDLE_ROOT)"

build-slint: ## Build the Rust Slint desktop app in release mode.
	cargo build --manifest-path exp-platform/rust/slint/Cargo.toml --release

run-slint: build-slint ## Run the Rust Slint desktop app (set BUNDLE=examples/WGSExtract).
	"$(SLINT_EXE)" --bundle "$(BUNDLE_ROOT)"

build-raygui: ## Build the Rust Raygui desktop app in release mode.
	cargo build --manifest-path exp-platform/rust/raygui/Cargo.toml --release

run-raygui: build-raygui ## Run the Rust Raygui desktop app (set BUNDLE=examples/WGSExtract).
	"$(RAYGUI_EXE)" --bundle "$(BUNDLE_ROOT)"

##@ Experimental C Platform

build-raygui-c: ## Build the C Raygui desktop app in release mode.
	cmake -S exp-platform/c/raygui -B "$(RAYGUI_C_BUILD_DIR)" -DCMAKE_BUILD_TYPE=Release
	cmake --build "$(RAYGUI_C_BUILD_DIR)" --config Release

run-raygui-c: build-raygui-c ## Run the C Raygui desktop app (set BUNDLE=examples/WGSExtract).
	"$(RAYGUI_C_EXE)" --bundle "$(BUNDLE_ROOT)" --repo-root "$(abspath .)"

##@ Experimental Rust Platform

build-imgui: ## Build the Rust Dear ImGui desktop app in release mode.
	cargo build --manifest-path exp-platform/rust/imgui/Cargo.toml --release

run-imgui: build-imgui ## Run the Rust Dear ImGui desktop app (set BUNDLE=examples/WGSExtract).
	"$(IMGUI_EXE)" --bundle "$(BUNDLE_ROOT)"

build-iced: ## Build the Rust Iced desktop app in release mode.
	cargo build --manifest-path exp-platform/rust/iced/Cargo.toml --release

run-iced: build-iced ## Run the Rust Iced desktop app (set BUNDLE=examples/WGSExtract).
	"$(ICED_EXE)" --bundle "$(BUNDLE_ROOT)"

build-makepad: ## Build the Rust Makepad desktop app in release mode.
	cargo build --manifest-path exp-platform/rust/makepad/Cargo.toml --release

run-makepad: build-makepad ## Run the Rust Makepad desktop app (set BUNDLE=examples/WGSExtract).
	"$(MAKEPAD_EXE)" --bundle "$(BUNDLE_ROOT)"

build-egui: ## Build the Rust egui desktop app in release mode.
	cargo build --manifest-path exp-platform/rust/egui/Cargo.toml --release

run-egui: build-egui ## Run the Rust egui desktop app (set BUNDLE=examples/WGSExtract).
	"$(EGUI_EXE)" --bundle "$(BUNDLE_ROOT)"

##@ Experimental C++ Platform

build-imgui-cpp: ## Build the C++ Dear ImGui desktop app in release mode.
	cmake -S exp-platform/cpp/imgui-cpp -B "$(IMGUI_CPP_BUILD_DIR)" -DCMAKE_BUILD_TYPE=Release
	cmake --build "$(IMGUI_CPP_BUILD_DIR)" --config Release

run-imgui-cpp: build-imgui-cpp ## Run the C++ Dear ImGui desktop app (set BUNDLE=examples/WGSExtract).
	"$(IMGUI_CPP_EXE)" --bundle "$(BUNDLE_ROOT)" --repo-root "$(abspath .)"

build-qt-qml: ## Build the Qt 6/QML desktop app in release mode.
	cmake -S exp-platform/cpp/qt-qml -B "$(QT_QML_BUILD_DIR)" -DCMAKE_BUILD_TYPE=Release
	cmake --build "$(QT_QML_BUILD_DIR)" --config Release

run-qt-qml: build-qt-qml ## Run the Qt 6/QML desktop app (set BUNDLE=examples/WGSExtract).
	"$(QT_QML_EXE)" --bundle "$(BUNDLE_ROOT)" --repo-root "$(abspath .)"

##@ Experimental .NET Platform

restore-avalonia: ## Restore the cross-platform Avalonia renderer projects.
	dotnet restore "$(AVALONIA_TEST_PROJECT)"

build-avalonia: restore-avalonia ## Build the cross-platform Avalonia renderer.
	dotnet build "$(AVALONIA_APP_PROJECT)" --no-restore

test-avalonia: restore-avalonia ## Run the Avalonia renderer validation tests.
	dotnet run --project "$(AVALONIA_TEST_PROJECT)" --no-restore

run-avalonia: build-avalonia ## Run the Avalonia renderer (set BUNDLE=examples/WGSExtract).
	dotnet run --project "$(AVALONIA_APP_PROJECT)" --no-restore -- --repo-root "$(abspath .)" --bundle "$(BUNDLE_ROOT)"

##@ Experimental Go Platform

build-fyne: ## Build the Go Fyne desktop app in development mode.
	mkdir -p out/dev
	cd exp-platform/go/fyne && $(FYNE_GO) build -o ../../../out/dev/gui-for-cli-fyne .

run-fyne: build-fyne ## Run the Go Fyne desktop app (set BUNDLE=examples/WGSExtract).
	GFC_FYNE_REPO_ROOT="$(abspath .)" GFC_FYNE_BUNDLE="$(BUNDLE_ROOT)" out/dev/gui-for-cli-fyne

##@ Experimental Dart Platform

flutter: ## Run the Flutter desktop app against examples/WGSExtract.
	cd exp-platform/dart/flutter && $(FLUTTER_CREATE_MACOS) && $(FLUTTER_DISABLE_SANDBOX) && $(FLUTTER_CONFIGURE_WINDOW) && $(FLUTTER_CLEAN_GENERATED) && flutter run -d macos --dart-define=GFC_REPO_ROOT="$(abspath .)" --dart-define=GFC_BUNDLE_ROOT="$(BUNDLE_ROOT)"

flutter-build: ## Build the Flutter desktop app for macOS.
	cd exp-platform/dart/flutter && $(FLUTTER_CREATE_MACOS) && $(FLUTTER_DISABLE_SANDBOX) && $(FLUTTER_CONFIGURE_WINDOW) && $(FLUTTER_CLEAN_GENERATED) && flutter build macos --release --dart-define=GFC_REPO_ROOT="$(abspath .)" --dart-define=GFC_BUNDLE_ROOT="$(BUNDLE_ROOT)"

##@ Experimental Kotlin Platform

build-android: ## Build the experimental Android Compose debug APK.
	cd "$(KOTLIN_COMPOSE_DIR)" && $(KOTLIN_ENV) $(KOTLIN_GRADLE) $(KOTLIN_GRADLE_FLAGS) :androidApp:assembleDebug

run-compose-desktop: ## Run the experimental Compose Multiplatform desktop app.
	cd "$(KOTLIN_COMPOSE_DIR)" && $(KOTLIN_ENV) $(KOTLIN_GRADLE) $(KOTLIN_GRADLE_FLAGS) :desktopApp:run --args="--bundle $(BUNDLE_ROOT)"

build-compose-desktop: ## Build the experimental Compose Multiplatform desktop package for this OS.
	cd "$(KOTLIN_COMPOSE_DIR)" && $(KOTLIN_ENV) $(KOTLIN_GRADLE) $(KOTLIN_GRADLE_FLAGS) :desktopApp:packageDistributionForCurrentOS

##@ Experimental Cross-Platform

launch-flutter-slint: build-macos build-tauri-release flutter-build build-slint ## Launch built Flutter, Slint, and SwiftUI apps for visual startup comparison.
	scripts/launch-flutter-slint.sh $(LAUNCH_ARGS)

##@ Stable Release Packages

build-webui-release: ## Build a standalone Web UI release folder with bundled Node.
	npm --prefix platform/typescript run build
	npm --prefix platform/typescript run tauri:prepare-node
	rm -rf "$(WEBUI_RELEASE_DIR)"
	mkdir -p "$(WEBUI_RELEASE_DIR)/platform/typescript/web" "$(WEBUI_RELEASE_DIR)/examples"
	ditto platform/typescript/dist "$(WEBUI_RELEASE_DIR)/platform/typescript/dist"
	ditto platform/typescript/web/vendor "$(WEBUI_RELEASE_DIR)/platform/typescript/web/vendor"
	cp platform/typescript/web/index.html platform/typescript/web/styles.css "$(WEBUI_RELEASE_DIR)/platform/typescript/web/"
	ditto platform/typescript/web/packagers/tauri/resources/node "$(WEBUI_RELEASE_DIR)/node"
	ditto examples/WGSExtract "$(WEBUI_RELEASE_DIR)/examples/WGSExtract"
	ditto resources "$(WEBUI_RELEASE_DIR)/resources"
	printf '%s\n' '#!/usr/bin/env sh' 'set -eu' 'cd "$$(dirname "$$0")"' 'exec ./node/bin/node platform/typescript/dist/web/src/server/main.js --bundle "$$(pwd)/examples/WGSExtract" "$$@"' > "$(WEBUI_RELEASE_DIR)/run-webui.sh"
	chmod +x "$(WEBUI_RELEASE_DIR)/run-webui.sh"

build-swift-release: project ## Build and stage the release SwiftUI macOS app.
	xcodebuild -workspace "$(APPLE_WORKSPACE)" -scheme GUIForCLIMac -configuration Release -derivedDataPath "$(DERIVED_DATA_PATH)" -destination '$(MACOS_DESTINATION)' build CODE_SIGNING_ALLOWED=NO
	rm -rf "$(SWIFT_RELEASE_DIR)"
	mkdir -p "$(SWIFT_RELEASE_DIR)"
	ditto "$(MACOS_RELEASE_APP)" "$(SWIFT_RELEASE_DIR)/$(APP_NAME).app"

##@ Experimental Apple Platform

build-appkit-release: project ## Build and stage the release AppKit macOS app.
	xcodebuild -workspace "$(APPLE_WORKSPACE)" -scheme GUIForCLIAppKit -configuration Release -derivedDataPath "$(DERIVED_DATA_PATH)" -destination '$(MACOS_DESTINATION)' build CODE_SIGNING_ALLOWED=NO
	rm -rf "$(APPKIT_RELEASE_DIR)"
	mkdir -p "$(APPKIT_RELEASE_DIR)"
	ditto "$(MACOS_APPKIT_RELEASE_APP)" "$(APPKIT_RELEASE_DIR)/$(APPKIT_APP_NAME).app"

##@ Stable TypeScript Packagers

build-webview-release: ## Build and stage the standalone native WKWebView Web UI shell app.
	npm --prefix platform/typescript run build
	npm --prefix platform/typescript run tauri:prepare-node
	rm -rf "$(WEBVIEW_RELEASE_DIR)"
	mkdir -p "$(WEBVIEW_RELEASE_DIR)/GUI for CLI WebView Shell.app/Contents/MacOS" "$(WEBVIEW_RELEASE_DIR)/GUI for CLI WebView Shell.app/Contents/Resources/platform/typescript/web" "$(WEBVIEW_RELEASE_DIR)/GUI for CLI WebView Shell.app/Contents/Resources/examples"
	cp platform/typescript/web/packagers/webview-shell/Info.plist "$(WEBVIEW_RELEASE_DIR)/GUI for CLI WebView Shell.app/Contents/Info.plist"
	swiftc -O -framework AppKit -framework WebKit platform/typescript/web/packagers/webview-shell/Shell.swift -o "$(WEBVIEW_RELEASE_DIR)/GUI for CLI WebView Shell.app/Contents/MacOS/GUIForCLIWebViewShell"
	ditto platform/typescript/dist "$(WEBVIEW_RELEASE_DIR)/GUI for CLI WebView Shell.app/Contents/Resources/platform/typescript/dist"
	ditto platform/typescript/web/vendor "$(WEBVIEW_RELEASE_DIR)/GUI for CLI WebView Shell.app/Contents/Resources/platform/typescript/web/vendor"
	cp platform/typescript/web/index.html platform/typescript/web/styles.css "$(WEBVIEW_RELEASE_DIR)/GUI for CLI WebView Shell.app/Contents/Resources/platform/typescript/web/"
	ditto platform/typescript/web/packagers/tauri/resources/node "$(WEBVIEW_RELEASE_DIR)/GUI for CLI WebView Shell.app/Contents/Resources/node"
	ditto examples/WGSExtract "$(WEBVIEW_RELEASE_DIR)/GUI for CLI WebView Shell.app/Contents/Resources/examples/WGSExtract"
	ditto resources "$(WEBVIEW_RELEASE_DIR)/GUI for CLI WebView Shell.app/Contents/Resources/resources"

build-tauri-release: ## Build and stage the standalone Tauri Web UI shell app.
	npm --prefix platform/typescript run tauri:build
	rm -rf "$(TAURI_RELEASE_DIR)"
	mkdir -p "$(TAURI_RELEASE_DIR)"
	ditto "$(WEBUI_TAURI_APP)" "$(TAURI_RELEASE_DIR)/GUI for CLI WebUI.app"

##@ Experimental Rust Platform

build-dioxus-release: build-webui-dioxus ## Build and stage the standalone Dioxus Native Web UI shell app.
	npm --prefix platform/typescript run tauri:prepare-node
	rm -rf "$(DIOXUS_RELEASE_DIR)"
	mkdir -p "$(DIOXUS_RELEASE_DIR)/platform/typescript/web" "$(DIOXUS_RELEASE_DIR)/examples"
	cp "$(RUST_APP_EXE)" "$(DIOXUS_RELEASE_DIR)/gui-for-cli-webui-dioxus"
	chmod +x "$(DIOXUS_RELEASE_DIR)/gui-for-cli-webui-dioxus"
	ditto platform/typescript/dist "$(DIOXUS_RELEASE_DIR)/platform/typescript/dist"
	ditto platform/typescript/web/vendor "$(DIOXUS_RELEASE_DIR)/platform/typescript/web/vendor"
	cp platform/typescript/web/index.html platform/typescript/web/styles.css "$(DIOXUS_RELEASE_DIR)/platform/typescript/web/"
	ditto platform/typescript/web/packagers/tauri/resources/node "$(DIOXUS_RELEASE_DIR)/node"
	ditto examples/WGSExtract "$(DIOXUS_RELEASE_DIR)/examples/WGSExtract"
	ditto resources "$(DIOXUS_RELEASE_DIR)/resources"

##@ Stable TypeScript Packagers

build-electron-release: ## Build and stage the standalone Electron Web UI shell app.
	npm --prefix platform/typescript run electron:package -- --out "$(abspath $(ELECTRON_RELEASE_DIR))"

##@ Experimental Go Platform

build-gio-release: ## Build and stage the standalone Go Gio app.
	rm -rf "$(GIO_RELEASE_DIR)"
	mkdir -p "$(GIO_RELEASE_DIR)/examples"
	cd exp-platform/go/gio && $(GIO_GO) build -trimpath -ldflags='-s -w' -o "../../../$(GIO_RELEASE_DIR)/gui-for-cli-gio" .
	ditto examples/WGSExtract "$(GIO_RELEASE_DIR)/examples/WGSExtract"
	ditto resources "$(GIO_RELEASE_DIR)/resources"

##@ Experimental .NET Platform

build-avalonia-release: ## Publish and stage the cross-platform Avalonia renderer.
	rm -rf "$(AVALONIA_RELEASE_DIR)"
	mkdir -p "$(AVALONIA_RELEASE_DIR)/examples"
	dotnet publish "$(AVALONIA_APP_PROJECT)" -c Release -o "$(abspath $(AVALONIA_RELEASE_DIR))/app"
	ditto examples/WGSExtract "$(AVALONIA_RELEASE_DIR)/examples/WGSExtract"
	ditto resources "$(AVALONIA_RELEASE_DIR)/resources"

##@ Experimental Go Platform

build-fyne-release: ## Build and stage the standalone Go Fyne app.
	rm -rf "$(FYNE_RELEASE_DIR)"
	mkdir -p "$(FYNE_RELEASE_DIR)/examples"
	cd exp-platform/go/fyne && $(FYNE_GO) build -trimpath -ldflags='-s -w' -o "../../../$(FYNE_RELEASE_DIR)/gui-for-cli-fyne" .
	ditto examples/WGSExtract "$(FYNE_RELEASE_DIR)/examples/WGSExtract"
	ditto resources "$(FYNE_RELEASE_DIR)/resources"

##@ Experimental Rust Platform

build-gtk4-release: build-gtk4 ## Build and stage the Rust GTK4/libadwaita desktop app.
	rm -rf "$(GTK4_RELEASE_DIR)"
	mkdir -p "$(GTK4_RELEASE_DIR)/examples"
	cp "$(GTK4_EXE)" "$(GTK4_RELEASE_DIR)/gui-for-cli-gtk4"
	ditto examples/WGSExtract "$(GTK4_RELEASE_DIR)/examples/WGSExtract"
	ditto resources "$(GTK4_RELEASE_DIR)/resources"

build-slint-release: build-slint ## Build and stage the Rust Slint desktop app.
	rm -rf "$(SLINT_RELEASE_DIR)"
	mkdir -p "$(SLINT_RELEASE_DIR)/examples"
	cp "$(SLINT_EXE)" "$(SLINT_RELEASE_DIR)/gui-for-cli-slint"
	ditto examples/WGSExtract "$(SLINT_RELEASE_DIR)/examples/WGSExtract"
	ditto resources "$(SLINT_RELEASE_DIR)/resources"

build-imgui-release: build-imgui ## Build and stage the Rust Dear ImGui desktop app.
	rm -rf "$(IMGUI_RELEASE_DIR)"
	mkdir -p "$(IMGUI_RELEASE_DIR)/examples"
	cp "$(IMGUI_EXE)" "$(IMGUI_RELEASE_DIR)/gui-for-cli-imgui"
	ditto examples/WGSExtract "$(IMGUI_RELEASE_DIR)/examples/WGSExtract"
	ditto resources "$(IMGUI_RELEASE_DIR)/resources"

build-iced-release: build-iced ## Build and stage the Rust Iced desktop app.
	rm -rf "$(ICED_RELEASE_DIR)"
	mkdir -p "$(ICED_RELEASE_DIR)/examples" "$(ICED_RELEASE_DIR)/platform/apple/shared/Sources/GUIForCLICore/Resources"
	cp "$(ICED_EXE)" "$(ICED_RELEASE_DIR)/gui-for-cli-iced"
	ditto examples/WGSExtract "$(ICED_RELEASE_DIR)/examples/WGSExtract"
	ditto platform/apple/shared/Sources/GUIForCLICore/Resources/BuiltinStrings "$(ICED_RELEASE_DIR)/platform/apple/shared/Sources/GUIForCLICore/Resources/BuiltinStrings"

build-makepad-release: build-makepad ## Build and stage the Rust Makepad desktop app.
	rm -rf "$(MAKEPAD_RELEASE_DIR)"
	mkdir -p "$(MAKEPAD_RELEASE_DIR)/examples" "$(MAKEPAD_RELEASE_DIR)/platform/apple/shared/Sources/GUIForCLICore/Resources"
	cp "$(MAKEPAD_EXE)" "$(MAKEPAD_RELEASE_DIR)/gui-for-cli-makepad"
	ditto examples/WGSExtract "$(MAKEPAD_RELEASE_DIR)/examples/WGSExtract"
	ditto platform/apple/shared/Sources/GUIForCLICore/Resources/BuiltinStrings "$(MAKEPAD_RELEASE_DIR)/platform/apple/shared/Sources/GUIForCLICore/Resources/BuiltinStrings"

build-egui-release: build-egui ## Build and stage the Rust egui desktop app.
	rm -rf "$(EGUI_RELEASE_DIR)"
	mkdir -p "$(EGUI_RELEASE_DIR)/examples"
	cp "$(EGUI_EXE)" "$(EGUI_RELEASE_DIR)/gui-for-cli-egui"
	ditto examples/WGSExtract "$(EGUI_RELEASE_DIR)/examples/WGSExtract"
	ditto resources "$(EGUI_RELEASE_DIR)/resources"

##@ Experimental C++ Platform

build-imgui-cpp-release: build-imgui-cpp ## Build and stage the C++ Dear ImGui desktop app.
	rm -rf "$(IMGUI_CPP_RELEASE_DIR)"
	mkdir -p "$(IMGUI_CPP_RELEASE_DIR)/examples"
	cp "$(IMGUI_CPP_EXE)" "$(IMGUI_CPP_RELEASE_DIR)/gui-for-cli-imgui-cpp"
	ditto examples/WGSExtract "$(IMGUI_CPP_RELEASE_DIR)/examples/WGSExtract"
	ditto resources "$(IMGUI_CPP_RELEASE_DIR)/resources"

build-qt-qml-release: build-qt-qml ## Build and stage the Qt 6/QML desktop app.
	rm -rf "$(QT_QML_RELEASE_DIR)"
	mkdir -p "$(QT_QML_RELEASE_DIR)/examples"
	cp "$(QT_QML_EXE)" "$(QT_QML_RELEASE_DIR)/gui-for-cli-qt-qml"
	ditto examples/WGSExtract "$(QT_QML_RELEASE_DIR)/examples/WGSExtract"
	ditto resources "$(QT_QML_RELEASE_DIR)/resources"

##@ Experimental Rust Platform

build-raygui-release: build-raygui ## Build and stage the Rust Raygui desktop app.
	rm -rf "$(RAYGUI_RELEASE_DIR)"
	mkdir -p "$(RAYGUI_RELEASE_DIR)/examples"
	cp "$(RAYGUI_EXE)" "$(RAYGUI_RELEASE_DIR)/gui-for-cli-raygui"
	ditto examples/WGSExtract "$(RAYGUI_RELEASE_DIR)/examples/WGSExtract"
	ditto resources "$(RAYGUI_RELEASE_DIR)/resources"

##@ Experimental C Platform

build-raygui-c-release: build-raygui-c ## Build and stage the C Raygui desktop app.
	rm -rf "$(RAYGUI_C_RELEASE_DIR)"
	mkdir -p "$(RAYGUI_C_RELEASE_DIR)/examples" "$(RAYGUI_C_RELEASE_DIR)/platform/apple/shared/Sources/GUIForCLICore/Resources"
	cp "$(RAYGUI_C_EXE)" "$(RAYGUI_C_RELEASE_DIR)/gui-for-cli-raygui-c"
	ditto examples/WGSExtract "$(RAYGUI_C_RELEASE_DIR)/examples/WGSExtract"
	ditto platform/apple/shared/Sources/GUIForCLICore/Resources/BuiltinStrings "$(RAYGUI_C_RELEASE_DIR)/platform/apple/shared/Sources/GUIForCLICore/Resources/BuiltinStrings"

##@ Experimental Dart Platform

build-flutter-release: flutter-build ## Build and stage the Flutter macOS desktop app.
	rm -rf "$(FLUTTER_RELEASE_DIR)"
	mkdir -p "$(FLUTTER_RELEASE_DIR)"
	ditto "$(FLUTTER_APP)" "$(FLUTTER_RELEASE_DIR)/GUI for CLI Flutter.app"

##@ Stable Release Packages

build-release-all: build-webui-release build-swift-release build-webview-release build-tauri-release build-electron-release ## Build stable release GUI options available in this checkout.

##@ Experimental Cross-Platform

build-release-all-prototypes: build-release-all build-appkit-release build-dioxus-release build-gio-release build-gtk4-release build-slint-release build-raygui-release build-raygui-c-release build-imgui-release build-iced-release build-makepad-release build-egui-release build-imgui-cpp-release build-qt-qml-release build-fyne-release build-avalonia-release build-flutter-release ## Include experimental prototype releases.

##@ Experimental Cross-Platform

measure-startup-sequential: build-macos build-tauri-release flutter-build build-slint ## Launch each GUI app sequentially for 2s, kill it, then continue.
	scripts/measure-startup-sequential.sh $(LAUNCH_ARGS)

##@ Experimental Python Platform

benchmark-toga: ## Benchmark the Python Toga/BeeWare renderer headlessly.
	mkdir -p "$(dir $(PYTHON_TOGA_BENCHMARK_OUTPUT))" "$(PYTHON_TOGA_WORKSPACE)"
	GUI_FOR_CLI_OFFLINE=1 $(PYTHON_TOGA_ENV) python3 -m gui_for_cli_toga --repo-root "$(abspath .)" --bundle "$(BUNDLE_ROOT)" --workspace-root "$(abspath $(PYTHON_TOGA_WORKSPACE))" --benchmark --benchmark-full --once --benchmark-output "$(PYTHON_TOGA_BENCHMARK_OUTPUT)"

##@ Experimental Go Platform

benchmark-gio-macos: build-gio-release ## Benchmark the staged Gio app startup on macOS (set SAMPLES=7).
	python3 scripts/benchmark-gio-macos.py --samples "$(BENCHMARK_SAMPLES)" --output "$(GIO_RELEASE_DIR)/benchmark-macos.json" "$(GIO_RELEASE_DIR)/gui-for-cli-gio"

##@ Experimental .NET Platform

benchmark-avalonia: restore-avalonia ## Print Avalonia first-render timing for the full WGSExtract bundle.
	dotnet build "$(AVALONIA_APP_PROJECT)" -c Release --no-restore
	GUI_FOR_CLI_OFFLINE=1 dotnet run --project "$(AVALONIA_APP_PROJECT)" -c Release --no-build --no-restore -- --repo-root "$(abspath .)" --bundle "$(BUNDLE_ROOT)" --benchmark --once

##@ Experimental Go Platform

benchmark-fyne-macos: build-fyne-release ## Benchmark the staged Fyne app startup on macOS (set SAMPLES=7).
	python3 scripts/benchmark-fyne-macos.py --samples "$(BENCHMARK_SAMPLES)" --output "$(FYNE_RELEASE_DIR)/benchmark-macos.json" "$(FYNE_RELEASE_DIR)/gui-for-cli-fyne"

##@ Experimental Dart Platform

benchmark-flutter: ## Run the Flutter app benchmark script (PowerShell, Windows desktop target).
	@if command -v pwsh >/dev/null 2>&1; then \
		pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/benchmark-flutter.ps1; \
	else \
		echo "Skipping Windows Flutter benchmark: pwsh is not installed." >&2; \
	fi

benchmark-flutter-macos: ## Benchmark the Flutter macOS desktop target.
	cd exp-platform/dart/flutter && $(FLUTTER_CREATE_MACOS) && $(FLUTTER_DISABLE_SANDBOX) && $(FLUTTER_CONFIGURE_WINDOW) && $(FLUTTER_CLEAN_GENERATED) && flutter build macos --release --dart-define=GFC_REPO_ROOT="$(abspath .)" --dart-define=GFC_BUNDLE_ROOT="$(BUNDLE_ROOT)" --dart-define=GFC_BENCHMARK_OUTPUT="$(FLUTTER_BENCHMARK_OUTPUT)"
	python3 scripts/benchmark-flutter-macos.py exp-platform/dart/flutter/build/macos/Build/Products/Release/gui_for_cli_flutter.app --marker "$(FLUTTER_BENCHMARK_OUTPUT)"

##@ Experimental Rust Platform

benchmark-gtk4: build-gtk4 ## Benchmark the Rust GTK4/libadwaita app with the full WGSExtract bundle.
	GUI_FOR_CLI_OFFLINE=1 "$(GTK4_EXE)" --bundle "$(BUNDLE_ROOT)" --benchmark --benchmark-full --once

benchmark-slint: build-slint ## Benchmark the Rust Slint desktop app with the full WGSExtract bundle.
	GUI_FOR_CLI_OFFLINE=1 "$(SLINT_EXE)" --bundle "$(BUNDLE_ROOT)" --benchmark --benchmark-full --once

benchmark-raygui: build-raygui ## Benchmark the Rust Raygui desktop app to first rendered frame.
	GUI_FOR_CLI_OFFLINE=1 "$(RAYGUI_EXE)" --bundle "$(BUNDLE_ROOT)" --benchmark --once

##@ Experimental C Platform

benchmark-raygui-c: build-raygui-c ## Benchmark the C Raygui desktop app with the full WGSExtract bundle.
	if command -v caffeinate >/dev/null 2>&1; then \
		caffeinate -u -t 5 env GUI_FOR_CLI_OFFLINE=1 "$(RAYGUI_C_EXE)" --bundle "$(BUNDLE_ROOT)" --repo-root "$(abspath .)" --benchmark --benchmark-full --once; \
	else \
		GUI_FOR_CLI_OFFLINE=1 "$(RAYGUI_C_EXE)" --bundle "$(BUNDLE_ROOT)" --repo-root "$(abspath .)" --benchmark --benchmark-full --once; \
	fi

##@ Experimental Rust Platform

benchmark-imgui: build-imgui ## Benchmark the Rust Dear ImGui desktop app with the full WGSExtract bundle.
	GUI_FOR_CLI_OFFLINE=1 "$(IMGUI_EXE)" --bundle "$(BUNDLE_ROOT)" --benchmark --benchmark-full --once

benchmark-iced: build-iced ## Benchmark the Rust Iced desktop app with the full WGSExtract bundle.
	rm -rf tmp/iced-workspaces
	mkdir -p "$(ICED_RELEASE_DIR)" tmp/iced-workspaces
	GUI_FOR_CLI_OFFLINE=1 GUI_FOR_CLI_BUNDLE_WORKSPACE_ROOT="$(abspath tmp/iced-workspaces)" "$(ICED_EXE)" --bundle "$(BUNDLE_ROOT)" --benchmark --benchmark-full --once --benchmark-output "$(ICED_RELEASE_DIR)/benchmark.txt"

benchmark-makepad: build-makepad ## Benchmark the Rust Makepad desktop app with the full WGSExtract bundle.
	GUI_FOR_CLI_OFFLINE=1 "$(MAKEPAD_EXE)" --bundle "$(BUNDLE_ROOT)" --benchmark --benchmark-full --once

benchmark-egui: build-egui ## Benchmark the Rust egui desktop app with the full WGSExtract bundle.
	GUI_FOR_CLI_OFFLINE=1 "$(EGUI_EXE)" --bundle "$(BUNDLE_ROOT)" --benchmark --benchmark-full --once

##@ Experimental C++ Platform

benchmark-imgui-cpp: build-imgui-cpp ## Benchmark the C++ Dear ImGui desktop app with the full WGSExtract bundle.
	GUI_FOR_CLI_OFFLINE=1 "$(IMGUI_CPP_EXE)" --bundle "$(BUNDLE_ROOT)" --repo-root "$(abspath .)" --benchmark --benchmark-full --once

benchmark-qt-qml: build-qt-qml ## Benchmark the Qt 6/QML desktop app with the full WGSExtract bundle.
	GUI_FOR_CLI_OFFLINE=1 "$(QT_QML_EXE)" --bundle "$(BUNDLE_ROOT)" --repo-root "$(abspath .)" --benchmark --benchmark-full --once

##@ Stable Apple Platform

build-macos: project ## Build the macOS desktop app.
	xcodebuild -workspace "$(APPLE_WORKSPACE)" -scheme GUIForCLIMac -configuration Debug -derivedDataPath "$(DERIVED_DATA_PATH)" -destination '$(MACOS_DESTINATION)' build CODE_SIGNING_ALLOWED=NO

mac: build-macos ## Build and run the macOS desktop app.
	open "$(MACOS_APP)"

##@ Experimental Apple Platform

build-macos-appkit: project ## Build the AppKit macOS desktop app.
	xcodebuild -workspace "$(APPLE_WORKSPACE)" -scheme GUIForCLIAppKit -configuration Debug -derivedDataPath "$(DERIVED_DATA_PATH)" -destination '$(MACOS_DESTINATION)' build CODE_SIGNING_ALLOWED=NO

appkit: build-macos-appkit ## Build and run the AppKit macOS desktop app.
	open "$(MACOS_APPKIT_APP)"

build-objc-appkit: project ## Build the Objective-C AppKit Test desktop app.
	xcodebuild -workspace "$(APPLE_WORKSPACE)" -scheme GUIForCLIObjCAppKit -configuration Debug -derivedDataPath "$(DERIVED_DATA_PATH)" -destination '$(MACOS_DESTINATION)' build CODE_SIGNING_ALLOWED=NO

objc-appkit: build-objc-appkit ## Build and run the Objective-C AppKit Test desktop app.
	GFC_REPO_ROOT="$(abspath .)" GFC_BUNDLE_PATH="$(BUNDLE_ROOT)" "$(OBJC_APPKIT_EXE)"

##@ Experimental Apple Platform

build-ios-sim: project ## Build the iOS simulator app.
	xcodebuild -workspace "$(APPLE_WORKSPACE)" -scheme GUIForCLIiOS -configuration Debug -derivedDataPath "$(DERIVED_DATA_PATH)" -destination '$(IOS_SIM_DESTINATION)' build CODE_SIGNING_ALLOWED=NO
	@if [ -L "$(IOS_SIM_DEMO_BUNDLE)" ]; then \
		echo "Materializing WGSExtract demo bundle for iOS simulator install"; \
		rm "$(IOS_SIM_DEMO_BUNDLE)"; \
		ditto "examples/WGSExtract" "$(IOS_SIM_DEMO_BUNDLE)"; \
	fi

build-ios-device: project ## Build the iOS device app. Optionally set IOS_DEVICE_DESTINATION.
	xcodebuild -workspace "$(APPLE_WORKSPACE)" -scheme GUIForCLIiOS -configuration Debug -derivedDataPath "$(DERIVED_DATA_PATH)" -destination '$(IOS_DEVICE_DESTINATION)' build CODE_SIGNING_ALLOWED=NO
	@if [ -L "$(IOS_DEVICE_DEMO_BUNDLE)" ]; then \
		echo "Materializing WGSExtract demo bundle for iOS device install"; \
		rm "$(IOS_DEVICE_DEMO_BUNDLE)"; \
		ditto "examples/WGSExtract" "$(IOS_DEVICE_DEMO_BUNDLE)"; \
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
	simulator_udid="$$(xcrun simctl getenv "$$simulator" SIMULATOR_UDID 2>/dev/null || printf '%s' "$$simulator")"; \
	open -a Simulator --args -CurrentDeviceUDID "$$simulator_udid"; \
	xcrun simctl install "$$simulator_udid" "$(IOS_SIM_APP)"; \
	xcrun simctl launch "$$simulator_udid" "$(IOS_BUNDLE_ID)"

ios-ipad-sim: build-ios-sim ## Build, install, and run on an iPad Simulator. Set IOS_IPAD_SIMULATOR if needed.
	@set -eu; \
	simulator="$(IOS_IPAD_SIMULATOR)"; \
	if [ "$$simulator" = "booted" ]; then \
		simulator="$$(xcrun simctl list devices booted | sed -nE '/iPad/s/.*\(([0-9A-F-]{36})\) \(Booted\).*/\1/p' | head -n 1)"; \
		if [ -z "$$simulator" ]; then \
			simulator="$$(xcrun simctl list devices available | sed -nE '/iPad/s/.*\(([0-9A-F-]{36})\) \(Shutdown\).*/\1/p' | head -n 1)"; \
			if [ -z "$$simulator" ]; then \
				echo "No booted or available iPad simulators found. Set IOS_IPAD_SIMULATOR to a simulator UDID or name." >&2; \
				exit 1; \
			fi; \
			echo "No iPad simulator is booted; booting $$simulator"; \
			xcrun simctl boot "$$simulator" || true; \
		fi; \
	else \
		xcrun simctl boot "$$simulator" || true; \
	fi; \
	xcrun simctl bootstatus "$$simulator" -b; \
	simulator_udid="$$(xcrun simctl getenv "$$simulator" SIMULATOR_UDID 2>/dev/null || printf '%s' "$$simulator")"; \
	open -a Simulator --args -CurrentDeviceUDID "$$simulator_udid"; \
	xcrun simctl install "$$simulator_udid" "$(IOS_SIM_APP)"; \
	xcrun simctl launch "$$simulator_udid" "$(IOS_BUNDLE_ID)"

ios-device: build-ios-device ## Build, install, and run on an iOS device. Set IOS_DEVICE to the device identifier.
	@if [ -n "$(IOS_DEVICE)" ]; then \
		xcrun devicectl device install app --device "$(IOS_DEVICE)" "$(IOS_DEVICE_APP)"; \
		xcrun devicectl device process launch --device "$(IOS_DEVICE)" "$(IOS_BUNDLE_ID)"; \
	else \
		echo "Skipping iOS device install: set IOS_DEVICE to a device identifier from: xcrun devicectl list devices" >&2; \
	fi

##@ Maintenance

clean: ## Remove SwiftPM, Tuist, build, and temporary outputs.
	$(SWIFT_GIT_ENV) swift package --package-path "$(APPLE_DIR)" clean
	rm -rf "$(APPLE_PROJECT)" "$(APPLE_WORKSPACE)" "$(APPLE_DIR)/Derived" "$(DERIVED_DATA_PATH)" "$(APPLE_DIR)/.build" "$(APPLE_DIR)/.swiftpm"
	rm -rf exp-platform/rust/raygui/target
	rm -rf exp-platform/c/raygui/build
	rm -rf exp-platform/rust/makepad/target
	rm -rf out/* tmp/*

cloc: ## Count lines of code, excluding gitignored files.
	@command -v cloc >/dev/null 2>&1 || (echo "cloc not found. Install with: brew install cloc" >&2; exit 1)
	cloc --vcs=git .

##@ CI

ci: ## Run the full CI pipeline locally (mirrors .github/workflows/ci.yml).
	python3 scripts/ci-local.py

ci-fast: ## Run the CI pipeline locally, skipping the iOS build.
	python3 scripts/ci-local.py --fast
