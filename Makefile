# HomePad build commands. Run `make help`.
SIM ?= iPad Pro 13-inch (M5)
DERIVED := .build/DerivedData
PROJECT := HomePad.xcodeproj
SCHEME := HomePad
# Device builds are optimized by default: SwiftUI in Debug drops frames. Use DEVICE_CONFIG=Debug to debug.
DEVICE_CONFIG ?= Release
PACKAGES := HomePadCore HomePadUI HomePadShell HomePadFaces HomePadAssistant HomePadSmartHome HomePadAudio HomePadPresence HomePadKitchen HomePadPersonal HomePadConnect HomePadCameraLab

.PHONY: help project build run test ui-test core-test devices device device-build device-install archive readme-images clean

help:
	@echo "make project        Regenerate HomePad.xcodeproj from project.yml (needs xcodegen)"
	@echo "make build          Build the app for the iPad simulator"
	@echo "make run            Build, install and launch in the simulator ($(SIM))"
	@echo "make test           Run Core unit tests on macOS, then every package's tests on the simulator"
	@echo "make devices        List connected devices and their identifiers"
	@echo "make device DEVICE=<id>  Build (Release, or DEVICE_CONFIG=Debug), sign (registering the iPad if needed), install and launch"
	@echo "make device-build   Signed build (DEVICE=<id> registers that iPad, otherwise generic)"
	@echo "make device-install Install the last device build (DEVICE=<id>)"
	@echo "make ui-test        Run the UI tests (taps and drags on real controls) in the simulator ($(SIM))"
	@echo "make readme-images  Capture simulator screenshots ($(SIM)) and compose docs/images (needs Pillow)"
	@echo "make clean          Remove build output"

project:
	xcodegen generate --quiet

build: project
	scripts/build-slot.sh xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIM)' -derivedDataPath $(DERIVED) -quiet build

run: build
	scripts/run-sim.sh "$(SIM)"

ui-test: project
	scripts/build-slot.sh xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIM)' -derivedDataPath .build/DerivedData-UITests \
		-only-testing:HomePadUITests test

core-test:
	cd Packages/HomePadCore && swift test

test: core-test
	@for p in $(PACKAGES); do \
		if [ "$$p" != HomePadCore ] && [ -d Packages/$$p/Tests ]; then \
			echo "== $$p"; scripts/build-package.sh $$p test || exit 1; \
		fi; \
	done

devices:
	xcrun devicectl list devices

device: device-build device-install

device-build: project
	@if [ -n "$(DEVICE)" ]; then dest='id=$(DEVICE)'; reg=-allowProvisioningDeviceRegistration; \
	else dest='generic/platform=iOS'; reg=; fi; \
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(DEVICE_CONFIG) -destination "$$dest" \
		-derivedDataPath $(DERIVED) -allowProvisioningUpdates $$reg -quiet build

device-install:
	DEVICE_CONFIG=$(DEVICE_CONFIG) scripts/install-device.sh "$(DEVICE)"

archive: project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'generic/platform=iOS' \
		-archivePath .build/HomePad.xcarchive -allowProvisioningUpdates archive

readme-images: build
	HOMEPAD_SIM="$(SIM)" python3 scripts/readme_images.py

clean:
	rm -rf .build
