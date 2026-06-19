APP_NAME = VoiceInput
BINARY = .build/release/$(APP_NAME)
APP_BUNDLE = .build/release/$(APP_NAME).app
PLIST = Sources/$(APP_NAME)/Info.plist
SIGNING_IDENTITY ?= -

.PHONY: build run install clean

build:
	swift build -c release --product $(APP_NAME)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	cp $(BINARY) $(APP_BUNDLE)/Contents/MacOS/
	cp $(PLIST) $(APP_BUNDLE)/Contents/
	echo "APPL????" > $(APP_BUNDLE)/Contents/PkgInfo
	codesign -s $(SIGNING_IDENTITY) --deep --force $(APP_BUNDLE)

run: build
	open $(APP_BUNDLE)

install: build
	cp -r $(APP_BUNDLE) /Applications/

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)
