# Mooring developer commands. See README.md.

SCHEME      := Mooring
PROJECT     := Mooring.xcodeproj
# Unsigned or CI-style builds must use another DERIVED (e.g. build/Unsigned):
# this one holds the app whose signed helper is registered with launchd.
DERIVED     ?= build/DerivedData
APP         := Mooring.app
INSTALL_DIR := /Applications
# `make uninstall` quits the app with this; its test swaps in a stub.
PKILL       ?= pkill
PACKAGES    := Packages/AwakeKit Packages/MooringIPC Packages/WindowKit Packages/ClipKit

# Extra xcodebuild settings, e.g. XCODEBUILD_FLAGS="CODE_SIGNING_ALLOWED=NO" in CI.
XCODEBUILD_FLAGS ?=

# -skipMacroValidation: WindowKit's Scribe dependency uses Swift macros, which need it non-interactively.
# -disableAutomaticPackageResolution: builds use exactly the pins in Config/Package.resolved.
# -packageAuthorizationProvider netrc: every package is public, so downloading Sparkle's binary never
# looks for GitHub credentials in the Keychain (which stops at an access prompt).
XCODEBUILD = xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED) \
	-destination 'platform=macOS,arch=$(shell uname -m)' -skipMacroValidation -disableAutomaticPackageResolution \
	-packageAuthorizationProvider netrc

# Pins for the gitignored project. Refresh: rm $(RESOLVED); xcodebuild -project $(PROJECT) -packageAuthorizationProvider netrc -resolvePackageDependencies; cp $(RESOLVED) Config/
RESOLVED    := $(PROJECT)/project.xcworkspace/xcshareddata/swiftpm/Package.resolved

.PHONY: bootstrap generate build run test lint install reset-sleep uninstall clean

bootstrap:
	brew list xcodegen >/dev/null 2>&1 || brew install xcodegen
	brew list swiftlint >/dev/null 2>&1 || brew install swiftlint
	xcodegen generate
	mkdir -p $(dir $(RESOLVED)) && cp Config/Package.resolved $(RESOLVED)

generate:
	xcodegen generate --quiet
	mkdir -p $(dir $(RESOLVED)) && cp Config/Package.resolved $(RESOLVED)

build: generate
	$(XCODEBUILD) -configuration Debug build $(XCODEBUILD_FLAGS)

# Waits for the old instance to exit: opening while it is still quitting just
# re-activates the dying process, leaving nothing running.
run: build
	-pkill -x Mooring
	@for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x Mooring >/dev/null || break; sleep 0.5; done
	open $(DERIVED)/Build/Products/Debug/$(APP)

test: generate
	@for pkg in $(PACKAGES); do echo "== swift test $$pkg"; (cd $$pkg && swift test) || exit 1; done
	bash scripts/test-mooring-hook.sh
	bash scripts/test-make-uninstall.sh
	$(XCODEBUILD) -configuration Debug test $(XCODEBUILD_FLAGS)

lint:
	swiftlint lint --quiet

install: generate
	$(XCODEBUILD) -configuration Release build $(XCODEBUILD_FLAGS)
	-pkill -x Mooring
	rm -rf $(INSTALL_DIR)/$(APP)
	ditto $(DERIVED)/Build/Products/Release/$(APP) $(INSTALL_DIR)/$(APP)

# Manual safety valve if lid sleep is ever left disabled.
reset-sleep:
	sudo pmset -a disablesleep 0

# Also removes ~/.local/bin/mooring, but only a link into the installed app. (Settings → Advanced →
# Uninstall Mooring… does the rest: helper, login item, plugin and settings.)
uninstall:
	-"$(PKILL)" -x Mooring
	@link="$(HOME)/.local/bin/mooring"; \
	if [ -L "$$link" ]; then \
		case "$$(readlink "$$link")" in \
			"$(INSTALL_DIR)/$(APP)"/*) rm -f "$$link" && echo "Removed $$link" ;; \
		esac; \
	fi
	rm -rf "$(INSTALL_DIR)/$(APP)"

clean:
	rm -rf build $(PROJECT)
