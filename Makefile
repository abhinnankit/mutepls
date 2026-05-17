SHELL := /bin/bash

APP_NAME := MutePls
APP_BUNDLE := /Applications/$(APP_NAME).app
RELEASE_BINARY := .build/release/mutepls

.PHONY: help build run package install open reinstall clean status

help:
	@echo "MutePls targets:"
	@echo "  make build      Build the release binary"
	@echo "  make run        Run the release binary from .build"
	@echo "  make package    Build dist/$(APP_NAME).app"
	@echo "  make install    Build and install $(APP_BUNDLE)"
	@echo "  make open       Open $(APP_BUNDLE)"
	@echo "  make reinstall  Install, restart the app, and open it"
	@echo "  make clean      Remove SwiftPM and packaged app artifacts"
	@echo "  make status     Show git status"

build:
	swift build -c release

run: build
	$(RELEASE_BINARY)

package:
	scripts/package-app.sh

install:
	scripts/install-app.sh

open:
	open "$(APP_BUNDLE)"

reinstall: install
	@killall "$(APP_NAME)" 2>/dev/null || true
	@sleep 0.5
	open -n "$(APP_BUNDLE)"

clean:
	rm -rf .build .swiftpm dist

status:
	git status --short --branch
