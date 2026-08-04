# GitHub Notifier — build system
# Single-command install: `make run` (build + assemble .app + launch)

APP_NAME    := GitHubNotifier
BUNDLE_ID   := com.ghnotifier.app
CONFIG      := release
BUILD_DIR   := .build/$(CONFIG)
APP_BUNDLE  := .build/$(APP_NAME).app
CONTENTS    := $(APP_BUNDLE)/Contents
INSTALL_DIR := /Applications

.PHONY: all build bundle sign kill run install update clean

all: bundle

## Compile the release binary
build:
	swift build -c $(CONFIG)

## Assemble the .app bundle (icon-less menu bar agent)
bundle: build
	@echo "==> Assembling $(APP_BUNDLE)"
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(CONTENTS)/MacOS"
	@mkdir -p "$(CONTENTS)/Resources"
	@cp "$(BUILD_DIR)/$(APP_NAME)" "$(CONTENTS)/MacOS/$(APP_NAME)"
	@cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	@cp Resources/AppIcon.icns "$(CONTENTS)/Resources/AppIcon.icns"
	@printf 'APPL????' > "$(CONTENTS)/PkgInfo"
	@$(MAKE) --no-print-directory sign
	@echo "==> Built $(APP_BUNDLE)"

## Ad-hoc sign so Keychain / notifications / ASWebAuthenticationSession behave
sign:
	@echo "==> Ad-hoc signing"
	@codesign --force --deep \
		--entitlements Resources/$(APP_NAME).entitlements \
		--sign - "$(APP_BUNDLE)" 2>/dev/null || \
		codesign --force --deep --sign - "$(APP_BUNDLE)"

## Quit every running instance (so a rebuild actually takes effect on relaunch)
kill:
	@pkill -f "$(APP_NAME).app/Contents/MacOS/$(APP_NAME)" 2>/dev/null || true

## Build, assemble, and (re)launch — quits the old instance first
run: bundle
	@echo "==> Restarting $(APP_NAME)"
	@pkill -f "$(APP_NAME).app/Contents/MacOS/$(APP_NAME)" 2>/dev/null || true
	@sleep 1
	@open "$(APP_BUNDLE)"

## Install to /Applications and relaunch from there
install: bundle
	@echo "==> Installing to $(INSTALL_DIR)"
	@pkill -f "$(APP_NAME).app/Contents/MacOS/$(APP_NAME)" 2>/dev/null || true
	@sleep 1
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@cp -R "$(APP_BUNDLE)" "$(INSTALL_DIR)/$(APP_NAME).app"
	@open "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "==> Installed and launched from $(INSTALL_DIR)."

## One-touch update for teammates: pull latest, rebuild, relaunch
update:
	@echo "==> Pulling latest"
	@git pull --ff-only
	@$(MAKE) --no-print-directory install

clean:
	swift package clean
	rm -rf .build/$(APP_NAME).app
