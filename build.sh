#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

TARGET="${1:-fat}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"

case "$TARGET" in
    clean)
        make clean
        echo "== build artifacts removed =="
        exit 0
        ;;
    fat|all|"")
        TARGET=fat
        OUT="build/OldSend.app"
        ;;
    armv6)
        OUT="build/OldSend.app"
        ;;
    armv7)
        OUT="build-armv7/OldSend.app"
        ;;
    *)
        echo "usage: $0 [fat|armv6|armv7|clean]" >&2
        exit 1
        ;;
esac

SDK="${SDK:-${TMPDIR:-/tmp}/sdk/iPhoneOS3.1.3.sdk}"
SDK_DYLIB="${SDK_DYLIB:-${TMPDIR:-/tmp}/sdk/iPhoneOS4.2.sdk}"

if [ ! -f "$SDK/System/Library/Frameworks/UIKit.framework/Headers/UIKit.h" ]; then
    echo "error: iPhoneOS3.1.3 SDK not found at $SDK" >&2
    echo "set SDK=/path/to/iPhoneOS3.1.3.sdk" >&2
    exit 1
fi

if ! xcrun -f clang >/dev/null 2>&1; then
    echo "error: clang not found (xcrun -f clang)" >&2
    exit 1
fi

if [ ! -f "$SDK_DYLIB/System/Library/Frameworks/UIKit.framework/Headers/UIKit.h" ]; then
    echo "error: iPhoneOS4.2 SDK not found at $SDK_DYLIB" >&2
    echo "set SDK_DYLIB=/path/to/iPhoneOS4.2.sdk" >&2
    exit 1
fi

if ! command -v ldid >/dev/null 2>&1; then
    echo "error: ldid not found in PATH" >&2
    exit 1
fi

make -j"$JOBS" SDK="$SDK" SDK_DYLIB="$SDK_DYLIB" "$TARGET"
file "$OUT/OldSend"
