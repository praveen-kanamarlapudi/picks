APP_NAME       := Picks
SCHEME         := Picks
CONFIGURATION  := Release
DERIVED        := .build
APP            := $(DERIVED)/Build/Products/$(CONFIGURATION)/$(APP_NAME).app
DIST           := dist
STAGE          := $(DIST)/dmg
DMG            := $(DIST)/$(APP_NAME).dmg
APPLICATIONS   := /Applications
PICKS_DATA     := $(HOME)/Library/Application Support/Picks
PICKS_CONTAINER := $(HOME)/Library/Containers/app.picks.mac/Data/Library/Application Support/Picks
KEEP_LEGACY    := $(HOME)/Library/Containers/app.keep.mac/Data/Library/Application Support/Keep
KEEP_SUPPORT   := $(HOME)/Library/Application Support/Keep
BACKUP_ROOT    := $(CURDIR)/backups

.PHONY: all help project build test dmg install uninstall backup clean

all: dmg install

help:
	@echo "make build      Build $(APP_NAME).app (Release)"
	@echo "make dmg        Build and package $(DMG)"
	@echo "make install    Backup catalogs, then build and copy $(APP_NAME).app to $(APPLICATIONS)"
	@echo "make uninstall  Remove $(APPLICATIONS)/$(APP_NAME).app"
	@echo "make backup     Copy catalogs (+ bookmarks) to $(BACKUP_ROOT)/picks-db-<timestamp>"
	@echo "make test       Run unit tests"
	@echo "make clean      Delete build and dist artifacts"

project:
	xcodegen generate

build: project
	xcodebuild \
		-scheme $(SCHEME) \
		-configuration $(CONFIGURATION) \
		-derivedDataPath $(DERIVED) \
		-destination 'platform=macOS' \
		build
	# Resign framework then app with the same ad-hoc identity.
	# Hardened-runtime + separate signatures is what made /Applications refuse to open.
	codesign --force --sign - --timestamp=none \
		"$(APP)/Contents/Frameworks/PicksCore.framework/Versions/A"
	codesign --force --sign - --timestamp=none \
		--entitlements Picks/Picks.entitlements \
		"$(APP)"

test: project
	xcodebuild \
		-scheme $(SCHEME) \
		-destination 'platform=macOS' \
		-derivedDataPath $(DERIVED) \
		test

dmg: build
	rm -rf $(STAGE)
	mkdir -p $(STAGE)
	cp -R "$(APP)" "$(STAGE)/"
	ln -s $(APPLICATIONS) "$(STAGE)/Applications"
	mkdir -p $(DIST)
	rm -f "$(DMG)"
	hdiutil create \
		-volname "$(APP_NAME)" \
		-srcfolder "$(STAGE)" \
		-ov \
		-format UDZO \
		"$(DMG)"
	@echo "DMG: $(DMG)"

install: backup build
	rm -rf "$(APPLICATIONS)/$(APP_NAME).app" "$(APPLICATIONS)/Keep.app"
	cp -R "$(APP)" "$(APPLICATIONS)/"
	@echo "Installed $(APPLICATIONS)/$(APP_NAME).app"

uninstall:
	rm -rf "$(APPLICATIONS)/$(APP_NAME).app"
	@echo "Removed $(APPLICATIONS)/$(APP_NAME).app"

# Consistent SQLite snapshot even if Picks is open. Thumbs are skipped (rebuildable).
# Copies every catalog root that actually has a DB (Picks and pre-rename Keep).
# Missing catalogs are fine so `make install` still works on a fresh machine.
backup:
	@set -euo pipefail; \
	stamp=$$(date +%Y%m%d-%H%M%S); \
	dest="$(BACKUP_ROOT)/picks-db-$$stamp"; \
	found=0; \
	mkdir -p "$(BACKUP_ROOT)"; \
	for spec in \
		"picks-container:$(PICKS_CONTAINER)" \
		"picks-support:$(PICKS_DATA)" \
		"keep-legacy:$(KEEP_LEGACY)" \
		"keep-support:$(KEEP_SUPPORT)"; do \
		label="$${spec%%:*}"; \
		data="$${spec#*:}"; \
		[ -d "$$data" ] || continue; \
		count=$$(find "$$data" -name 'catalog.sqlite' 2>/dev/null | wc -l | tr -d ' '); \
		[ "$$count" -gt 0 ] || continue; \
		found=1; \
		mkdir -p "$$dest"; \
		find "$$data" \( -name 'catalog.sqlite' -o -name 'folder.bookmark' \) -print0 \
		| while IFS= read -r -d '' f; do \
			rel="$${f#$$data/}"; \
			out="$$dest/$$rel"; \
			if [ -e "$$out" ]; then out="$$dest/$$label/$$rel"; fi; \
			mkdir -p "$$(dirname "$$out")"; \
			case "$$f" in \
				*.sqlite) sqlite3 "$$f" ".backup '$$out'" ;; \
				*) cp "$$f" "$$out" ;; \
			esac; \
		done; \
		echo "Backed up $$count catalog(s) from $$data"; \
	done; \
	if [ "$$found" -eq 0 ]; then \
		echo "No catalogs to backup"; \
	else \
		echo "Backup: $$dest"; \
	fi

clean:
	rm -rf $(DERIVED) $(DIST) Picks.xcodeproj/xcuserdata
