.DEFAULT_GOAL := generate
SIMULATOR ?= 412F4437-7BD7-44D1-AA3D-2B7158090E14
.PHONY: fonts generate build preview test test-ios test-links
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
	python3 scripts/cross-process-test.py
test-ios: generate
	xcodebuild -project Madar.xcodeproj -scheme Madar -destination 'platform=iOS Simulator,id=$(SIMULATOR)' -derivedDataPath DerivedData -resultBundlePath Artifacts/M0-tests-$$(date +%s).xcresult CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES test
test-links: generate
	SIMULATOR=$(SIMULATOR) python3 scripts/deep-link-test.py
