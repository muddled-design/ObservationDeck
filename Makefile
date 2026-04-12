APP_NAME     := ClaudeMonitor
SCHEME       := ClaudeMonitor
PROJECT      := ObservationDeck.xcodeproj
BUILD_DIR    := build
ARCHIVE_PATH := $(BUILD_DIR)/$(APP_NAME).xcarchive
EXPORT_PATH  := $(BUILD_DIR)/export
APP_BUNDLE   := $(EXPORT_PATH)/$(APP_NAME).app
DMG_PATH     := $(BUILD_DIR)/$(APP_NAME).dmg

# Required for archive/export/notarize — pass via env or command line
TEAM_ID           ?=
APPLE_ID          ?=
NOTARIZE_PASSWORD ?=

.PHONY: project archive export notarize dmg release clean

project:
	xcodegen generate

archive:
	$(if $(TEAM_ID),,$(error TEAM_ID is required))
	xcodebuild archive \
		-scheme $(SCHEME) \
		-configuration Release \
		-archivePath $(ARCHIVE_PATH) \
		CODE_SIGN_STYLE=Manual \
		CODE_SIGN_IDENTITY="Developer ID Application" \
		DEVELOPMENT_TEAM=$(TEAM_ID)

export:
	$(if $(TEAM_ID),,$(error TEAM_ID is required))
	plutil -replace teamID -string "$(TEAM_ID)" ExportOptions.plist -o $(BUILD_DIR)/ExportOptions.plist
	xcodebuild -exportArchive \
		-archivePath $(ARCHIVE_PATH) \
		-exportPath $(EXPORT_PATH) \
		-exportOptionsPlist $(BUILD_DIR)/ExportOptions.plist

notarize:
	$(if $(APPLE_ID),,$(error APPLE_ID is required))
	$(if $(NOTARIZE_PASSWORD),,$(error NOTARIZE_PASSWORD is required))
	$(if $(TEAM_ID),,$(error TEAM_ID is required))
	ditto -c -k --keepParent $(APP_BUNDLE) $(BUILD_DIR)/$(APP_NAME)-notarization.zip
	xcrun notarytool submit $(BUILD_DIR)/$(APP_NAME)-notarization.zip \
		--apple-id "$(APPLE_ID)" \
		--password "$(NOTARIZE_PASSWORD)" \
		--team-id "$(TEAM_ID)" \
		--wait
	xcrun stapler staple $(APP_BUNDLE)
	xcrun stapler validate $(APP_BUNDLE)

dmg:
	mkdir -p $(BUILD_DIR)/dmg-staging
	cp -R $(APP_BUNDLE) $(BUILD_DIR)/dmg-staging/
	ln -sf /Applications $(BUILD_DIR)/dmg-staging/Applications
	hdiutil create -volname "$(APP_NAME)" \
		-srcfolder $(BUILD_DIR)/dmg-staging \
		-ov -format UDZO \
		$(DMG_PATH)
	rm -r $(BUILD_DIR)/dmg-staging
	@echo ""
	@echo "DMG: $(DMG_PATH)"
	@echo "SHA256: $$(shasum -a 256 $(DMG_PATH) | cut -d' ' -f1)"

release: project archive export notarize dmg

clean:
	rm -rf $(BUILD_DIR) $(PROJECT) SupportFiles
