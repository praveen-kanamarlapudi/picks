APP_NAME       := Keep
SCHEME         := Keep
CONFIGURATION  := Release
DERIVED        := .build
APP            := $(DERIVED)/Build/Products/$(CONFIGURATION)/$(APP_NAME).app
DIST           := dist
STAGE          := $(DIST)/dmg
DMG            := $(DIST)/$(APP_NAME).dmg
APPLICATIONS   := /Applications
KEEP_DATA      := $(HOME)/Library/Containers/app.keep.mac/Data/Library/Application Support/Keep
BACKUP_ROOT    := $(CURDIR)/backups

.PHONY: all help project build test dmg install uninstall backup clean

all: dmg install

help:
	@echo "make build      Build $(APP_NAME).app (Release)"
	@echo "make dmg        Build and package $(DMG)"
	@echo "make install    Build and copy $(APP_NAME).app to $(APPLICATIONS)"
	@echo "make uninstall  Remove $(APPLICATIONS)/$(APP_NAME).app"
	@echo "make backup     Copy catalogs (+ bookmarks) to $(BACKUP_ROOT)/keep-db-<timestamp>"
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
		"$(APP)/Contents/Frameworks/KeepCore.framework/Versions/A"
	codesign --force --sign - --timestamp=none \
		--entitlements Keep/Keep.entitlements \
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

install: build
	rm -rf "$(APPLICATIONS)/$(APP_NAME).app"
	cp -R "$(APP)" "$(APPLICATIONS)/"
	@echo "Installed $(APPLICATIONS)/$(APP_NAME).app"

uninstall:
	rm -rf "$(APPLICATIONS)/$(APP_NAME).app"
	@echo "Removed $(APPLICATIONS)/$(APP_NAME).app"

# Consistent SQLite snapshot even if Keep is open. Thumbs are skipped (rebuildable).
backup:
	@test -d "$(KEEP_DATA)" || (echo "No Keep data at $(KEEP_DATA)"; exit 1)
	@mkdir -p "$(BACKUP_ROOT)"
	@stamp=$$(date +%Y%m%d-%H%M%S); \
	dest="$(BACKUP_ROOT)/keep-db-$$stamp"; \
	mkdir -p "$$dest"; \
	find "$(KEEP_DATA)" \( -name 'catalog.sqlite' -o -name 'catalog.sqlite-wal' -o -name 'catalog.sqlite-shm' -o -name 'folder.bookmark' \) -print0 \
	| while IFS= read -r -d '' f; do \
		rel="$${f#$(KEEP_DATA)/}"; \
		mkdir -p "$$dest/$$(dirname "$$rel")"; \
		case "$$f" in \
			*.sqlite) sqlite3 "$$f" ".backup '$$dest/$$rel'" ;; \
			*) cp "$$f" "$$dest/$$rel" ;; \
		esac; \
	done; \
	echo "Backed up to $$dest"

clean:
	rm -rf $(DERIVED) $(DIST) Keep.xcodeproj/xcuserdata
