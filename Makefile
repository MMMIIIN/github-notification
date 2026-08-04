# GitHub Notifier — build system
# Single-command install: `make run` (build + assemble .app + launch)

APP_NAME    := GitHubNotifier
BUNDLE_ID   := com.ghnotifier.app
CONFIG      := release
BUILD_DIR   := .build/$(CONFIG)
APP_BUNDLE  := .build/$(APP_NAME).app
CONTENTS    := $(APP_BUNDLE)/Contents
INSTALL_DIR := /Applications

.PHONY: all build bundle sign run install clean

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

## Build, assemble, and launch
run: bundle
	@echo "==> Launching $(APP_NAME)"
	@open "$(APP_BUNDLE)"

## Install to /Applications
install: bundle
	@echo "==> Installing to $(INSTALL_DIR)"
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@cp -R "$(APP_BUNDLE)" "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "==> Installed. Launch it from /Applications or Spotlight."

clean:
	swift package clean
	rm -rf .build/$(APP_NAME).app
