# Snapper — SwiftPM build + hand-assembled .app bundle.
# There is no Xcode on this machine (Command Line Tools only), so no xcodebuild and no .xcodeproj.

NAME        := Snapper
BUNDLE_ID   := com.zikopoulos.snapper
# Single source of truth for the release number: the VERSION file. The Info.plist, the package name
# and the git tag all come from here, so they cannot drift apart. Override for a one-off build only.
VERSION     ?= $(shell cat VERSION 2>/dev/null || echo 0.0.0)
BUILD       := $(shell date +%Y%m%d%H%M)
CONFIG      := release

BUILD_DIR   := .build/$(CONFIG)
DIST        := dist
APP         := $(DIST)/$(NAME).app
CONTENTS    := $(APP)/Contents
MACOS_DIR   := $(CONTENTS)/MacOS
RES_DIR     := $(CONTENTS)/Resources

PKG         := $(DIST)/$(NAME)-$(VERSION).pkg
ZIP         := $(DIST)/$(NAME)-$(VERSION).zip

# Signing identity, in order of preference.
#
#   1. A real "Developer ID Application" certificate, if one is installed. Only this can be
#      notarized, and only a notarized app opens on someone else's Mac without a warning.
#   2. The local self-signed "Snapper Dev" certificate from `make cert`. Not distributable, but it
#      keeps the designated requirement stable so Screen Recording permission survives rebuilds.
#   3. Ad-hoc. The signature changes every build, so macOS treats each build as a new app and
#      re-asks for permission.
#
# Override with CODESIGN_IDENTITY="..." to force one.
SIGN_KEYCHAIN := snapper-signing.keychain
KEYCHAIN_PW   := $(HOME)/Library/Application Support/com.zikopoulos.snapper/signing/keychain-password
DIST_KEYCHAIN := snapper-distribution.keychain
DIST_PW       := $(HOME)/Library/Application Support/com.zikopoulos.snapper/distribution/keychain-password

LOCAL_CERT    := $(shell security find-identity -p codesigning $(SIGN_KEYCHAIN) 2>/dev/null | grep -c "Snapper Dev" || echo 0)
DEVELOPER_ID  := $(shell security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)

ifneq ($(DEVELOPER_ID),)
CODESIGN_IDENTITY ?= $(DEVELOPER_ID)
else ifeq ($(LOCAL_CERT),0)
CODESIGN_IDENTITY ?= -
else
CODESIGN_IDENTITY ?= Snapper Dev
endif

# ~/Applications needs no admin rights and is still a stable path, which is what the Screen
# Recording permission actually cares about. Override with INSTALL_DIR=/Applications to install
# system-wide (that one will ask for your password).
INSTALL_DIR ?= $(HOME)/Applications

.PHONY: all build bundle sign app run install test clean uninstall reset-permissions \
        cert cert-remove developer-id installer-id notary-setup pkg zip notarize verify release identity icon \
        reset-settings

all: app

build:
	swift build -c $(CONFIG) --product $(NAME)

bundle: build
	@rm -rf "$(APP)"
	@mkdir -p "$(MACOS_DIR)" "$(RES_DIR)"
	@cp "$(BUILD_DIR)/$(NAME)" "$(MACOS_DIR)/$(NAME)"
	@sed -e 's/__NAME__/$(NAME)/g' \
	     -e 's/__BUNDLE_ID__/$(BUNDLE_ID)/g' \
	     -e 's/__VERSION__/$(VERSION)/g' \
	     -e 's/__BUILD__/$(BUILD)/g' \
	     Resources/Info.plist.in > "$(CONTENTS)/Info.plist"
	@printf 'APPL????' > "$(CONTENTS)/PkgInfo"
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$(RES_DIR)/AppIcon.icns"; fi
	@plutil -lint "$(CONTENTS)/Info.plist" > /dev/null
	@echo "bundled → $(APP)  ($(VERSION), build $(BUILD))"

sign: bundle
	@if [ "$(CODESIGN_IDENTITY)" = "-" ]; then \
		echo "signing ad-hoc — permission re-prompts after each rebuild (run 'make cert' to fix)"; \
		codesign --force --sign - "$(APP)"; \
	elif [ "$(CODESIGN_IDENTITY)" = "Snapper Dev" ]; then \
		if [ -f "$(KEYCHAIN_PW)" ]; then \
			security unlock-keychain -p "$$(cat "$(KEYCHAIN_PW)")" $(SIGN_KEYCHAIN) 2>/dev/null || true; \
		fi; \
		echo "signing with the local 'Snapper Dev' certificate — not notarizable"; \
		codesign --force --keychain $(SIGN_KEYCHAIN) --sign "Snapper Dev" "$(APP)"; \
	else \
		if [ -f "$(DIST_PW)" ]; then \
			security unlock-keychain -p "$$(cat "$(DIST_PW)")" $(DIST_KEYCHAIN) 2>/dev/null || true; \
		fi; \
		echo "signing with '$(CODESIGN_IDENTITY)'"; \
		echo "  + hardened runtime and a secure timestamp, both required for notarization"; \
		codesign --force --options runtime --timestamp --sign "$(CODESIGN_IDENTITY)" "$(APP)"; \
	fi
	@codesign --verify --verbose=1 "$(APP)" 2>&1 | sed 's/^/  /'
	@codesign -d -r- "$(APP)" 2>&1 | grep designated | sed 's/^/  /'

app: sign

run: app
	-@pkill -x $(NAME) 2>/dev/null || true
	@open "$(APP)"
	@echo "launched $(NAME) — look for the camera icon in the menu bar"

install: app
	-@pkill -x $(NAME) 2>/dev/null || true
	@mkdir -p "$(INSTALL_DIR)"
	@rm -rf "$(INSTALL_DIR)/$(NAME).app"
	@cp -R "$(APP)" "$(INSTALL_DIR)/"
	@echo "installed → $(INSTALL_DIR)/$(NAME).app"
	@# This target rebuilds, which re-signs with a fresh build number and so discards any
	@# notarization ticket. That is fine for a local install — a bundle built here carries no
	@# quarantine attribute, so Gatekeeper never gates the launch — but `make notarize && make
	@# install` would otherwise leave an unnotarized build behind with nothing to say so.
	@if ! xcrun stapler validate "$(INSTALL_DIR)/$(NAME).app" >/dev/null 2>&1; then \
		echo "  note: this build is not notarized — fine locally, not what you would distribute."; \
		echo "        for a build to hand to someone else: make notarize (or make release)"; \
	else \
		echo "  notarization ticket is stapled"; \
	fi

test:
	@swift run -c debug SnapperTests

clean:
	swift package clean
	@rm -rf "$(DIST)"

uninstall:
	-@pkill -x $(NAME) 2>/dev/null || true
	@rm -rf "$(INSTALL_DIR)/$(NAME).app"

# Shows which of the three signing paths this machine will take, and why.
identity:
	@echo "identity in use: $(CODESIGN_IDENTITY)"
	@if [ -n "$(DEVELOPER_ID)" ]; then \
		echo "  app signing:   yes — the app can be notarized"; \
	else \
		echo "  app signing:   no  — run 'make developer-id'"; \
	fi
	@if [ -n "$(INSTALLER_ID)" ]; then \
		echo "  pkg signing:   $(INSTALLER_ID)"; \
	else \
		echo "  pkg signing:   no  — run 'make installer-id'"; \
	fi
	@echo
	@echo "Apple-issued identities (these chain to a trusted root):"
	@security find-identity -v -p codesigning 2>/dev/null | sed 's/^/  /'
	@echo "every identity codesign can use, self-signed included:"
	@security find-identity -p codesigning $(SIGN_KEYCHAIN) 2>/dev/null | sed -n 's/^ *[0-9]) /  /p'

# Regenerates the app icon from scripts/make-icon.swift. The .icns is committed, so this only
# needs running when the artwork changes.
icon:
	@swift scripts/make-icon.swift
	@iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
	@echo "wrote Resources/AppIcon.icns"

# Creates the local signing identity that keeps Screen Recording permission stable across rebuilds.
cert:
	@./scripts/setup-signing.sh

cert-remove:
	-@security delete-keychain $(SIGN_KEYCHAIN) 2>/dev/null || true
	-@rm -f "$(KEYCHAIN_PW)"
	@echo "removed the local signing identity; builds fall back to ad-hoc"

# Clears the app's stored settings, so the next launch behaves like a genuine first run — the setup
# window included.
#
# Worth knowing why this is needed at all: UserDefaults live in ~/Library/Preferences keyed by bundle
# id and owned by the user, not inside the .app. Uninstalling and reinstalling does not touch them,
# so `hasCompletedSetup` survives and the setup window never reappears.
reset-settings:
	-@pkill -x $(NAME) 2>/dev/null || true
	@# Waiting for the process to actually be gone, not a fixed sleep. SIGTERM makes the app flush
	@# its cached UserDefaults on the way out, so clearing them while it is still exiting lets it
	@# write the old values back afterwards — the reset reports success and the next launch still
	@# skips setup.
	@for i in $$(seq 1 40); do \
		pgrep -x $(NAME) >/dev/null 2>&1 || break; \
		sleep 0.25; \
	done
	@if pgrep -x $(NAME) >/dev/null 2>&1; then \
		echo "$(NAME) is still running and will not quit — close it and try again"; \
		exit 1; \
	fi
	@sleep 1
	@if [ -f "$(HOME)/Library/Preferences/$(BUNDLE_ID).plist" ]; then \
		cp "$(HOME)/Library/Preferences/$(BUNDLE_ID).plist" "$(HOME)/Library/Preferences/$(BUNDLE_ID).plist.bak"; \
		echo "backed up → ~/Library/Preferences/$(BUNDLE_ID).plist.bak"; \
	fi
	@# Order matters, and getting it wrong is silent. cfprefsd owns a write-behind cache for this
	@# domain: killing it *after* `defaults delete` discards the deletion and it writes the old
	@# values back out as it exits, so the reset appears to succeed and changes nothing. Drop the
	@# cache first, then remove the file, then delete the domain.
	-@killall -u "$$(id -un)" cfprefsd 2>/dev/null || true
	@sleep 1
	-@rm -f "$(HOME)/Library/Preferences/$(BUNDLE_ID).plist" 2>/dev/null || true
	-@defaults delete $(BUNDLE_ID) 2>/dev/null || true
	@sleep 1
	@# Verified rather than assumed, because the failure mode above leaves no trace.
	@if defaults read $(BUNDLE_ID) >/dev/null 2>&1; then \
		echo "FAILED — settings survived:"; \
		defaults read $(BUNDLE_ID) | sed 's/^/    /'; \
		echo "  quit $(NAME) and try again"; \
		exit 1; \
	else \
		echo "cleared settings for $(BUNDLE_ID) — the next launch runs setup from scratch"; \
	fi

# Clears this app's TCC entries so the permission prompt appears again from scratch.
reset-permissions:
	-@tccutil reset ScreenCapture $(BUNDLE_ID) 2>/dev/null || true
	-@tccutil reset SystemPolicyDesktopFolder $(BUNDLE_ID) 2>/dev/null || true
	@echo "cleared TCC entries for $(BUNDLE_ID)"

# ----------------------------------------------------------------- distribution

# One-time setup for shipping builds other people can open.
developer-id:
	@./scripts/setup-developer-id.sh request application

# The second certificate, needed only to sign the installer package.
installer-id:
	@./scripts/setup-developer-id.sh request installer

notary-setup:
	@./scripts/setup-notarization.sh

# Signing a package uses a "Developer ID Installer" certificate, which is a different certificate
# from the "Developer ID Application" one that signs the app.
INSTALLER_ID := $(shell security find-identity -v -p basic 2>/dev/null | sed -n 's/.*"\(Developer ID Installer: [^"]*\)".*/\1/p' | head -1)

pkg: app
	@INSTALLER_IDENTITY="$(INSTALLER_ID)" ./scripts/make-pkg.sh "$(APP)" "$(VERSION)"

# The zip is what a future in-app updater would download; the installer is what a person downloads.
# ditto rather than zip, because a .app's symlinks and extended attributes matter.
zip: app
	@rm -f "$(ZIP)"
	@/usr/bin/ditto -c -k --keepParent "$(APP)" "$(ZIP)"
	@echo "$(ZIP)  ($$(du -h "$(ZIP)" | cut -f1))"

notarize: app
	@./scripts/notarize.sh "$(APP)"

# What Gatekeeper will conclude on someone else's Mac.
verify:
	@echo "signature:"
	@codesign -dvv "$(APP)" 2>&1 | sed 's/^/  /'
	@echo "notarization ticket:"
	@xcrun stapler validate "$(APP)" 2>&1 | sed 's/^/  /' || true
	@echo "Gatekeeper:"
	@spctl --assess --type exec -vvv "$(APP)" 2>&1 | sed 's/^/  /' || true

# Full release: test, build, notarize, package, publish to GitHub.
release:
	@./scripts/release.sh $(VERSION)
