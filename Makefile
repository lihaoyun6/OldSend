APP        := OldSend
SDK        ?= sdk/iPhoneOS3.1.3.sdk
SDK_DYLIB  ?= sdk/iPhoneOS4.2.sdk
CC         := $(shell xcrun -f clang)
LIPO       := $(shell xcrun -f lipo)
LDID       ?= ldid
ENTITLEMENTS := client/OldSend.entitlements

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
              client/ReceiveWifiLarge-iPad@2x.png \
              client/ReceiveWifiLargeBlue-iPad@2x.png \
              client/ReceiveWifiLargeBlue-iPad.png \
              client/ReceiveWifiLargeBlue.png \
              client/DeviceMobile.png client/DeviceDesktop.png client/DeviceWeb.png \
              client/DeviceHeadless.png client/DeviceServer.png \
              client/SettingsBackground.png client/RandomAlias.png client/MediaVideoIcon.png
LAUNCH_IMAGES := client/Default.png client/Default@2x.png \
                 client/Default-Portrait~ipad.png client/Default-Portrait@2x~ipad.png \
                 client/Default-Landscape~ipad.png client/Default-Landscape@2x~ipad.png \
                 client/Default-Portrait.png client/Default-Portrait@2x.png \
                 client/Default-Landscape.png client/Default-Landscape@2x.png
UI_IMAGES  += client/TabReceive@2x.png client/TabSend@2x.png \
              client/TabSettings@2x.png client/TabHistory@2x.png \
              client/ReceiveWifiLarge@2x.png client/ReceiveWifiLargeBlue@2x.png \
              client/DeviceMobile@2x.png client/DeviceDesktop@2x.png \
              client/DeviceWeb@2x.png client/DeviceHeadless@2x.png \
              client/DeviceServer@2x.png \
              client/RandomAlias@2x.png client/MediaVideoIcon@2x.png \
              client/HomeButton.png client/HomeButton@2x.png
TYPE_ICONS := $(wildcard client/icons/*.png)
UI_ICONS   := client/Icon.png client/Icon@2x.png \
              client/Icon-Small.png client/Icon-Small@2x.png \
              client/Icon-72.png client/Icon-72@2x.png \
              client/Icon-Small-50.png client/Icon-Small-50@2x.png
L10N       := client/en.lproj/Localizable.strings \
              client/zh_CN.lproj/Localizable.strings \
              client/zh-Hans.lproj/Localizable.strings \
              client/zh-Hant.lproj/Localizable.strings

DEBUG ?= 0
CFLAGS_COMMON := -isysroot $(SDK) -O2 -marm -mno-thumb \
                 -fno-objc-arc -fno-stack-protector \
                 -Iclient -Ivendor -Ivendor/mbedtls/include \
                 -Wno-deprecated-declarations
ifeq ($(DEBUG),1)
CFLAGS_COMMON += -DDEBUG
endif
CFLAGS_armv6  := -target armv6-apple-ios3.1.3 $(CFLAGS_COMMON)
CFLAGS_armv7  := -target armv7-apple-ios3.1.3 $(CFLAGS_COMMON)
LDFLAGS := -framework UIKit -framework Foundation -framework QuartzCore \
           -framework CoreGraphics -framework SystemConfiguration

MEDIA_DYLIB := $(BUILD)/MediaPicker.dylib
ASSET_DYLIB := $(BUILD)/AssetImporter.dylib

.PHONY: all fat armv6 armv7 bundle clean check-sdk

all: fat

fat: $(BUILD)/OldSend-fat $(MEDIA_DYLIB) $(ASSET_DYLIB)
	@$(MAKE) --no-print-directory bundle \
		BUNDLE=build/$(APP).app \
		BUNDLE_BINARY=$(BUILD)/OldSend-fat \
		MEDIA_DYLIB=$(MEDIA_DYLIB) \
		ASSET_DYLIB=$(ASSET_DYLIB)

armv6: $(BUILD)/OldSend-armv6 $(MEDIA_DYLIB) $(ASSET_DYLIB)
	@$(MAKE) --no-print-directory bundle \
		BUNDLE=build/$(APP).app \
		BUNDLE_BINARY=$(BUILD)/OldSend-armv6 \
		MEDIA_DYLIB=$(MEDIA_DYLIB) \
		ASSET_DYLIB=$(ASSET_DYLIB)

armv7: $(BUILD)/OldSend-armv7 $(MEDIA_DYLIB) $(ASSET_DYLIB)
	@$(MAKE) --no-print-directory bundle \
		BUNDLE=build-armv7/$(APP).app \
		BUNDLE_BINARY=$(BUILD)/OldSend-armv7 \
		MEDIA_DYLIB=$(MEDIA_DYLIB) \
		ASSET_DYLIB=$(ASSET_DYLIB)

bundle: $(BUNDLE_BINARY) $(MEDIA_DYLIB) $(ASSET_DYLIB) \
        client/Info.plist $(ENTITLEMENTS) $(UI_ICONS) $(UI_IMAGES) $(LAUNCH_IMAGES) $(L10N)
	@rm -rf $(BUNDLE)
	@mkdir -p $(BUNDLE)/en.lproj $(BUNDLE)/zh_CN.lproj $(BUNDLE)/zh-Hans.lproj $(BUNDLE)/zh-Hant.lproj
	@cp $(BUNDLE_BINARY) $(BUNDLE)/$(APP)
	@$(LDID) -S$(ENTITLEMENTS) $(BUNDLE)/$(APP)
	@cp client/Info.plist $(BUNDLE)/Info.plist
	@cp $(UI_ICONS) $(BUNDLE)/
	@cp $(UI_IMAGES) $(BUNDLE)/
	@cp $(LAUNCH_IMAGES) $(BUNDLE)/
	@cp $(TYPE_ICONS) $(BUNDLE)/
	@if [ -n "$(MEDIA_DYLIB)" ]; then \
		cp $(MEDIA_DYLIB) $(BUNDLE)/MediaPicker.dylib; \
		chmod 755 $(BUNDLE)/MediaPicker.dylib; \
	fi
	@if [ -n "$(ASSET_DYLIB)" ]; then \
		cp $(ASSET_DYLIB) $(BUNDLE)/AssetImporter.dylib; \
		chmod 755 $(BUNDLE)/AssetImporter.dylib; \
	fi
	@cp client/en.lproj/Localizable.strings $(BUNDLE)/en.lproj/Localizable.strings
	@cp client/zh_CN.lproj/Localizable.strings $(BUNDLE)/zh_CN.lproj/Localizable.strings
	@cp client/zh-Hans.lproj/Localizable.strings $(BUNDLE)/zh-Hans.lproj/Localizable.strings
	@cp client/zh-Hant.lproj/Localizable.strings $(BUNDLE)/zh-Hant.lproj/Localizable.strings
	@chmod 755 $(BUNDLE)/$(APP)
	@chmod 644 $(BUNDLE)/Info.plist $(UI_ICONS) $(UI_IMAGES) $(LAUNCH_IMAGES) $(TYPE_ICONS) \
	            $(BUNDLE)/en.lproj/Localizable.strings \
	            $(BUNDLE)/zh_CN.lproj/Localizable.strings \
	            $(BUNDLE)/zh-Hans.lproj/Localizable.strings \
	            $(BUNDLE)/zh-Hant.lproj/Localizable.strings

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


$(BUILD)/AssetImporter-armv6.dylib: media/AssetImporter.m
	@mkdir -p $(dir $@)
	$(CC) -target armv6-apple-ios4.0 -isysroot $(SDK_DYLIB) -O2 -marm -mno-thumb \
		-fno-objc-arc -fblocks \
		-dynamiclib -install_name @executable_path/AssetImporter.dylib \
		-framework Foundation -framework AssetsLibrary \
		media/AssetImporter.m -o $@

$(BUILD)/AssetImporter-armv7.dylib: media/AssetImporter.m
	@mkdir -p $(dir $@)
	$(CC) -target armv7-apple-ios4.0 -isysroot $(SDK_DYLIB) -O2 -marm -mno-thumb \
		-fno-objc-arc -fblocks \
		-dynamiclib -install_name @executable_path/AssetImporter.dylib \
		-framework Foundation -framework AssetsLibrary \
		media/AssetImporter.m -o $@

$(BUILD)/AssetImporter.dylib: $(BUILD)/AssetImporter-armv6.dylib $(BUILD)/AssetImporter-armv7.dylib
	$(LIPO) -create $(BUILD)/AssetImporter-armv6.dylib $(BUILD)/AssetImporter-armv7.dylib -output $@
	@$(LDID) -S $@

$(BUILD)/OldSend-fat: $(BUILD)/OldSend-armv6 $(BUILD)/OldSend-armv7
	$(LIPO) -create $(BUILD)/OldSend-armv6 $(BUILD)/OldSend-armv7 -output $@

$(BUILD)/OldSend-armv6: $(ARM6_OBJ)
	$(CC) $(CFLAGS_armv6) $(ARM6_OBJ) $(LDFLAGS) -o $@

# iPad 3/4 依据 App 链接时记录的 UIKit 版本决定是否用 2x 原生分辨率渲染。
# 4.3 SDK 记录的是 1500.0.0（会被当作 legacy，1x），这里改成 iOS 6 的版本号。
UIKIT_LINK_VERSION ?= 2380.17.0

$(BUILD)/OldSend-armv7: $(ARM7_OBJ)
	$(CC) $(CFLAGS_armv7) $(ARM7_OBJ) $(LDFLAGS) -o $@
	python3 tools/set-dylib-version.py $@ UIKit $(UIKIT_LINK_VERSION)

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
