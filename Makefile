APP_NAME     := CmdTab
BUILD_DIR    := build
APP_PATH     := $(BUILD_DIR)/Build/Products/Release/$(APP_NAME).app
INSTALL_PATH := /Applications/$(APP_NAME).app
XCODEBUILD   := xcodebuild -project $(APP_NAME).xcodeproj -scheme $(APP_NAME) -derivedDataPath $(BUILD_DIR) -quiet

# Sign with your own Apple team: make install DEVELOPMENT_TEAM=YOURTEAMID
DEVELOPMENT_TEAM ?=
SIGNING := $(if $(DEVELOPMENT_TEAM),DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM),)

.PHONY: project build test ci install clean

project: ## Generate the Xcode project from project.yml
	xcodegen generate --quiet

build: project ## Build a signed Release app into ./build
	$(XCODEBUILD) -configuration Release $(SIGNING) build

test: project ## Run the unit tests
	$(XCODEBUILD) $(SIGNING) test

ci: project ## Run the unit tests without code signing (CI, contributors without a team)
	$(XCODEBUILD) CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" test

install: build ## Build and copy the app to /Applications (quits a running copy first)
	-pkill -x $(APP_NAME); sleep 0.5
	rm -rf "$(INSTALL_PATH)"
	cp -R "$(APP_PATH)" "$(INSTALL_PATH)"
	open "$(INSTALL_PATH)"

clean:
	rm -rf $(BUILD_DIR) $(APP_NAME).xcodeproj
