# Mooring developer commands. See README.md.

SCHEME      := Mooring
PROJECT     := Mooring.xcodeproj
DERIVED     := build/DerivedData
APP         := Mooring.app
INSTALL_DIR := /Applications
PACKAGES    := Packages/AwakeKit Packages/MooringIPC

# Extra xcodebuild settings, e.g. XCODEBUILD_FLAGS="CODE_SIGNING_ALLOWED=NO" in CI.
XCODEBUILD_FLAGS ?=

XCODEBUILD = xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED) \
	-destination 'platform=macOS,arch=$(shell uname -m)'

.PHONY: bootstrap generate build run test lint install reset-sleep uninstall clean

bootstrap:
	brew list xcodegen >/dev/null 2>&1 || brew install xcodegen
	brew list swiftlint >/dev/null 2>&1 || brew install swiftlint
	xcodegen generate

generate:
	xcodegen generate --quiet

build: generate
	$(XCODEBUILD) -configuration Debug build $(XCODEBUILD_FLAGS)

run: build
	-pkill -x Mooring
	open $(DERIVED)/Build/Products/Debug/$(APP)

test: generate
	@for pkg in $(PACKAGES); do echo "== swift test $$pkg"; (cd $$pkg && swift test) || exit 1; done
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

uninstall:
	-pkill -x Mooring
	rm -rf $(INSTALL_DIR)/$(APP)

clean:
	rm -rf build $(PROJECT)
