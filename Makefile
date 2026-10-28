APP        := OldSend
SDK        ?= $(TMPDIR)sdk/iPhoneOS3.1.3.sdk
SDK_DYLIB  ?= $(TMPDIR)sdk/iPhoneOS4.2.sdk
CC         := $(shell xcrun -f clang)
LIPO       := $(shell xcrun -f lipo)
LDID       ?= ldid

BUILD      := build
BUNDLE     ?= $(BUILD)/$(APP).app
BUNDLE_BINARY ?= $(BUILD)/OldSend-fat

CLIENT_SRC := $(wildcard client/*.m)
MBED_SRC   := $(wildcard vendor/mbedtls/library/*.c)
CJSON_SRC  := vendor/cJSON.c

ARM6_OBJ   := $(patsubst client/%.m,$(BUILD)/armv6/client/%.o,$(CLIENT_SRC)) \
              $(patsubst vendor/mbedtls/library/%.c,$(BUILD)/armv6/mbed/%.o,$(MBED_SRC)) \
              $(BUILD)/armv6/cJSON.o
ARM7_OBJ   := $(patsubst client/%.m,$(BUILD)/armv7/client/%.o,$(CLIENT_SRC)) \
              $(patsubst vendor/mbedtls/library/%.c,$(BUILD)/armv7/mbed/%.o,$(MBED_SRC)) \
              $(BUILD)/armv7/cJSON.o

UI_IMAGES  := client/TabReceive.png client/TabSend.png client/TabSettings.png \
              client/TabHistory.png \
              client/ReceiveWifiLarge.png \
              client/ReceiveWifiLarge-iPad.png \
              client/ReceiveWifiLargeBlue-iPad.png \
              client/ReceiveWifiLargeBlue.png \
              client/DeviceMobile.png client/DeviceDesktop.png client/DeviceWeb.png \
              client/DeviceHeadless.png client/DeviceServer.png \
              client/SettingsBackground.png client/RandomAlias.png client/MediaVideoIcon.png
TYPE_ICONS := $(wildcard client/icons/*.png)
UI_ICONS   := client/Icon.png client/Icon-Small.png client/Icon-Small-50.png \
              client/Icon-72.png
L10N       := client/en.lproj/Localizable.strings client/zh_CN.lproj/Localizable.strings

CFLAGS_COMMON := -isysroot $(SDK) -O2 -marm -mno-thumb \
                 -fno-objc-arc -fno-stack-protector \
                 -Iclient -Ivendor -Ivendor/mbedtls/include \
                 -Wno-deprecated-declarations
CFLAGS_armv6  := -target armv6-apple-ios3.1.3 $(CFLAGS_COMMON)
CFLAGS_armv7  := -target armv7-apple-ios3.1.3 $(CFLAGS_COMMON)
LDFLAGS := -framework UIKit -framework Foundation -framework QuartzCore \
           -framework CoreGraphics -framework SystemConfiguration

MEDIA_DYLIB := $(BUILD)/MediaPicker.dylib

.PHONY: all fat armv6 armv7 bundle clean check-sdk

all: fat

fat: $(BUILD)/OldSend-fat $(MEDIA_DYLIB)
	@$(MAKE) --no-print-directory bundle \
		BUNDLE=build/$(APP).app \
		BUNDLE_BINARY=$(BUILD)/OldSend-fat \
		MEDIA_DYLIB=$(MEDIA_DYLIB)

armv6: $(BUILD)/OldSend-armv6 $(MEDIA_DYLIB)
	@$(MAKE) --no-print-directory bundle \
		BUNDLE=build/$(APP).app \
		BUNDLE_BINARY=$(BUILD)/OldSend-armv6 \
		MEDIA_DYLIB=$(MEDIA_DYLIB)

armv7: $(BUILD)/OldSend-armv7 $(MEDIA_DYLIB)
	@$(MAKE) --no-print-directory bundle \
		BUNDLE=build-armv7/$(APP).app \
		BUNDLE_BINARY=$(BUILD)/OldSend-armv7 \
		MEDIA_DYLIB=$(MEDIA_DYLIB)

bundle: $(BUNDLE_BINARY) $(MEDIA_DYLIB) \
        client/Info.plist $(UI_ICONS) $(UI_IMAGES) $(L10N)
	@rm -rf $(BUNDLE)
	@mkdir -p $(BUNDLE)/en.lproj $(BUNDLE)/zh_CN.lproj
	@cp $(BUNDLE_BINARY) $(BUNDLE)/$(APP)
	@$(LDID) -S $(BUNDLE)/$(APP)
	@cp client/Info.plist $(BUNDLE)/Info.plist
	@cp $(UI_ICONS) $(BUNDLE)/
	@cp $(UI_IMAGES) $(BUNDLE)/
	@cp $(TYPE_ICONS) $(BUNDLE)/
	@if [ -n "$(MEDIA_DYLIB)" ]; then \
		cp $(MEDIA_DYLIB) $(BUNDLE)/MediaPicker.dylib; \
		chmod 755 $(BUNDLE)/MediaPicker.dylib; \
	fi
	@cp client/en.lproj/Localizable.strings $(BUNDLE)/en.lproj/Localizable.strings
	@cp client/zh_CN.lproj/Localizable.strings $(BUNDLE)/zh_CN.lproj/Localizable.strings
	@chmod 755 $(BUNDLE)/$(APP)
	@chmod 644 $(BUNDLE)/Info.plist $(UI_ICONS) $(UI_IMAGES) $(TYPE_ICONS) \
	            $(BUNDLE)/en.lproj/Localizable.strings \
	            $(BUNDLE)/zh_CN.lproj/Localizable.strings

$(BUILD)/MediaPicker-armv6.dylib: media/MediaPickerViewController.m client/MediaPickerViewController.h
	@mkdir -p $(dir $@)
	$(CC) -target armv6-apple-ios4.0 -isysroot $(SDK_DYLIB) -O2 -marm -mno-thumb \
		-fno-objc-arc -fblocks -Iclient \
		-dynamiclib -install_name @executable_path/MediaPicker.dylib \
		-framework UIKit -framework Foundation -framework QuartzCore \
		-framework CoreGraphics -framework AssetsLibrary \
		media/MediaPickerViewController.m -o $@

$(BUILD)/MediaPicker-armv7.dylib: media/MediaPickerViewController.m client/MediaPickerViewController.h
	@mkdir -p $(dir $@)
	$(CC) -target armv7-apple-ios4.0 -isysroot $(SDK_DYLIB) -O2 -marm -mno-thumb \
		-fno-objc-arc -fblocks -Iclient \
		-dynamiclib -install_name @executable_path/MediaPicker.dylib \
		-framework UIKit -framework Foundation -framework QuartzCore \
		-framework CoreGraphics -framework AssetsLibrary \
		media/MediaPickerViewController.m -o $@

$(BUILD)/MediaPicker.dylib: $(BUILD)/MediaPicker-armv6.dylib $(BUILD)/MediaPicker-armv7.dylib
	$(LIPO) -create $(BUILD)/MediaPicker-armv6.dylib $(BUILD)/MediaPicker-armv7.dylib -output $@
	@$(LDID) -S $@

$(BUILD)/OldSend-fat: $(BUILD)/OldSend-armv6 $(BUILD)/OldSend-armv7
	$(LIPO) -create $(BUILD)/OldSend-armv6 $(BUILD)/OldSend-armv7 -output $@

$(BUILD)/OldSend-armv6: $(ARM6_OBJ)
	$(CC) $(CFLAGS_armv6) $(ARM6_OBJ) $(LDFLAGS) -o $@

$(BUILD)/OldSend-armv7: $(ARM7_OBJ)
	$(CC) $(CFLAGS_armv7) $(ARM7_OBJ) $(LDFLAGS) -o $@

$(BUILD)/armv6/client/%.o: client/%.m
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS_armv6) -c $< -o $@

$(BUILD)/armv7/client/%.o: client/%.m
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS_armv7) -c $< -o $@

$(BUILD)/armv6/cJSON.o: $(CJSON_SRC)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS_armv6) -c $< -o $@

$(BUILD)/armv7/cJSON.o: $(CJSON_SRC)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS_armv7) -c $< -o $@

$(BUILD)/armv6/mbed/%.o: vendor/mbedtls/library/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS_armv6) -c $< -o $@

$(BUILD)/armv7/mbed/%.o: vendor/mbedtls/library/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS_armv7) -c $< -o $@

check-sdk:
	@test -f "$(SDK)/System/Library/Frameworks/UIKit.framework/Headers/UIKit.h" || { \
	  echo "error: SDK not found at $(SDK)"; exit 1; }

clean:
	rm -rf $(BUILD) build-armv7
