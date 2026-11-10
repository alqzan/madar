.DEFAULT_GOAL := generate
SIMULATOR := 390840AD-4FF0-476F-8E1D-E0C521A58E45
ifneq ($(SIMULATOR),390840AD-4FF0-476F-8E1D-E0C521A58E45)
$(error Only the approved Madar 15 Pro Max iOS 27.0 simulator may be used)
endif
.PHONY: fonts generate build preview test test-ios test-links cloud-device
fonts:
	python3 scripts/prepare-workspace.py
generate: fonts
	xcodegen generate
build: generate
	xcodebuild -project Madar.xcodeproj -scheme Madar -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
preview: generate
	xcodebuild -project Madar.xcodeproj -scheme Madar -destination 'platform=iOS Simulator,id=$(SIMULATOR)' -derivedDataPath DerivedData CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build
	xcrun simctl bootstatus $(SIMULATOR) -b
	xcrun simctl install $(SIMULATOR) DerivedData/Build/Products/Debug-iphonesimulator/Madar.app
	xcrun simctl launch $(SIMULATOR) com.alqzan.madar2
test:
	swift test --package-path Packages/MadarCore
	swift test --package-path Packages/MadarData
	swift test --package-path Packages/MadarSnapshots
	swift test --package-path Packages/MadarCommands
	swift test --package-path Packages/MadarMoney
	swift test --package-path Packages/MadarPrayer
	swift test --package-path Packages/MadarQuran
	swift test --package-path Packages/MadarInbox
	swift test --package-path Packages/MadarSync
	python3 scripts/cross-process-test.py
test-ios: generate
	xcodebuild -project Madar.xcodeproj -scheme Madar -destination 'platform=iOS Simulator,id=$(SIMULATOR)' -derivedDataPath DerivedData -resultBundlePath Artifacts/M0-tests-$$(date +%s).xcresult CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES test
test-links: generate
	SIMULATOR=$(SIMULATOR) python3 scripts/deep-link-test.py
# Deferred under RA1. Retained command is guarded against accidental activation.
cloud-device:
	@test "$(CLOUDKIT_OWNER_AUTHORIZED)" = "YES" || (echo "CloudKit is deferred under RA1; explicit owner authorization required."; exit 1)
	$(MAKE) generate
	xcodebuild -project Madar.xcodeproj -scheme Madar -destination 'generic/platform=iOS' -derivedDataPath DerivedData -allowProvisioningUpdates DEVELOPMENT_TEAM=$(TEAM) MADAR_CLOUDKIT_CONTAINER=iCloud.com.alqzan.madar2 MADAR_APP_ENTITLEMENTS=App/Madar-CloudKit.entitlements build
