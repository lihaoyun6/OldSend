#
<p align="center">
<img src="./client/Icon-72.png" />
<h1 align="center">OldSend</h1>
<h3 align="center">A native LocalSend-compatible client for iOS 3.1.3 and later</h3>
</p>

[简体中文](README_zh.md)

## Preview

![OldSend preview](preview.png)

## Features

- Native Objective-C / UIKit app for iPhone OS 3.1.3 (armv6) and iPad 1 / iOS 4.3 (armv7). No Flutter, Electron, or web runtime.
- LocalSend protocol v2.2: multicast discovery, register, prepare-upload, upload, and cancel.
- TLS 1.2 through bundled mbedTLS 2.28.8. Identity is an ECDSA P-256 self-signed certificate; the fingerprint is the uppercase SHA-256 of the DER certificate.
- Receive: explicit accept prompt by default, or quick save. Photos and videos are copied to Camera Roll while an app copy stays in History; text messages open in a read-only viewer without being persisted.
- Send: queue files, photos, text, and clipboard content in one transfer. The Files picker browses the device filesystem (starting at `/var/mobile`) and supports multi-select across folders. On iOS 4+, photos and videos use a custom multi-select grid; iOS 3 falls back to the system picker.
- Progress HUD with cancel, including cancelling while waiting for the receiver to accept.
- History: file type icons, swipe to delete, edit mode with multi-select, and the current directory shown at the bottom.
- Settings: nickname with random generator, quick save, listening address, and version. Native iPad layout with landscape and popovers; iPhone / iPod stay in portrait.
- English and Simplified Chinese interfaces.

> A jailbroken device is required. OldSend is installed as a system app under `/Applications`.

## Installation

Download the `.deb` or `.ipa` from the `release/` directory.

- `.deb`: install with Cydia, iFile or `dpkg -i OldSend_v1.0.0_iphoneos-arm.deb`.
- `.ipa`: install with AppSync / `installipa` on a jailbroken device. It is not an App Store-signed IPA.

## Build

Requirements: macOS, Xcode command line tools, the iPhoneOS 3.1.3 SDK, the iPhoneOS 4.2 SDK, and `ldid`.

```bash
export SDK=/path/to/iPhoneOS3.1.3.sdk
export SDK_DYLIB=/path/to/iPhoneOS4.2.sdk

./build.sh            # universal armv6 + armv7 -> build/OldSend.app
./build.sh armv6      # armv6 only -> build/OldSend.app
./build.sh armv7      # armv7 only -> build-armv7/OldSend.app
./build.sh clean      # remove build/ and build-armv7/
```

The main app is built with the 3.1.3 SDK. The photo/video picker lives in `MediaPicker.dylib`, built separately with the 4.2 SDK for armv6 + armv7 with a minimum of iOS 4.0. On iOS 3 the dylib fails to load and the app falls back to the system picker.

`JOBS=N ./build.sh` controls parallel compilation. The SDKs default to `$TMPDIR/sdk/iPhoneOS3.1.3.sdk` and `$TMPDIR/sdk/iPhoneOS4.2.sdk`; override them with `SDK=` and `SDK_DYLIB=`.

To deploy manually:

```bash
scp -r build/OldSend.app root@<device-address>:/Applications/
ssh root@<device-address> 'killall -9 SpringBoard'
```

Launch OldSend from the home screen after SpringBoard restarts.

## Third-party

- [mbedTLS](https://github.com/Mbed-TLS/mbedtls) — Apache-2.0
- [cJSON](https://github.com/DaveGamble/cJSON) — MIT
- The History tab icon is derived from [Material Icons](https://github.com/google/material-design-icons) — Apache-2.0

> OldSend is an independent project and is not affiliated with the LocalSend project.
