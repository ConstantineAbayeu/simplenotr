APP_NAME   = SimpleNotr
BUNDLE     = $(APP_NAME).app
BINARY     = .build/release/$(APP_NAME)
BUNDLE_ID  = com.simplenotr.app
VERSION    = 1.0.0

# ── Targets ──────────────────────────────────────────────────────────────────

.PHONY: run build app clean

## Run in development mode (debug build, immediate launch)
run:
	swift run

## Build a release binary (no .app bundle — useful for quick checks)
build:
	swift build -c release

## Build a self-contained .app bundle you can double-click or copy to /Applications
app: build
	@echo "→ Creating $(BUNDLE)…"
	@rm -rf "$(BUNDLE)"
	@mkdir -p "$(BUNDLE)/Contents/MacOS"
	@mkdir -p "$(BUNDLE)/Contents/Resources"
	@cp "$(BINARY)" "$(BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable       string $(APP_NAME)"    \
	                         -c "Add :CFBundleIdentifier       string $(BUNDLE_ID)"   \
	                         -c "Add :CFBundleName             string $(APP_NAME)"    \
	                         -c "Add :CFBundleDisplayName      string $(APP_NAME)"    \
	                         -c "Add :CFBundleVersion          string $(VERSION)"     \
	                         -c "Add :CFBundleShortVersionString string $(VERSION)"   \
	                         -c "Add :CFBundlePackageType      string APPL"           \
	                         -c "Add :CFBundleInfoDictionaryVersion string 6.0"       \
	                         -c "Add :LSMinimumSystemVersion   string 13.0"           \
	                         -c "Add :NSHighResolutionCapable  bool   true"           \
	                         -c "Add :NSSupportsAutomaticGraphicsSwitching bool true" \
	                         -c "Add :NSPrincipalClass         string NSApplication"  \
	                         "$(BUNDLE)/Contents/Info.plist" 2>/dev/null; true
	@echo "✓ $(BUNDLE) ready — open it with:"
	@echo "    open $(BUNDLE)"

## Remove build artifacts and the .app bundle
clean:
	@swift package clean
	@rm -rf "$(BUNDLE)"
	@echo "✓ Clean"
