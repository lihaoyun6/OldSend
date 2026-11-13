#!/usr/bin/env python3
"""Set the recorded current version of one linked dylib in a 32-bit Mach-O.

iOS picks the iPad render scale from the UIKit version the app was linked
against: apps recording the iOS 4.3 UIKit version (1500.0.0) are treated as
legacy and get UIScreen.scale == 1 on iPad 3/4, while apps recording a 6.x
UIKit version get scale == 2.  The 4.3 SDK has to be used for iOS 3 runtime
compatibility, so the recorded value is raised after linking.

Only LC_LOAD_DYLIB.current_version is changed; the compatibility version that
dyld actually enforces is left untouched.
"""

import struct
import sys


def main():
    if len(sys.argv) != 4:
        sys.exit("usage: set-dylib-version.py <mach-o> <libname> <x.y.z>")

    path, libname, version = sys.argv[1], sys.argv[2], sys.argv[3]
    parts = [int(x) for x in version.split(".")]
    if len(parts) != 3:
        sys.exit("version must be x.y.z")

    data = bytearray(open(path, "rb").read())
    magic = struct.unpack_from("<I", data, 0)[0]
    if magic != 0xFEEDFACE:
        sys.exit("%s: not a 32-bit Mach-O" % path)

    ncmds = struct.unpack_from("<I", data, 16)[0]
    off = 28
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", data, off)
        if cmd in (0xC, 0x80000018):  # LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB
            nameoff = struct.unpack_from("<I", data, off + 8)[0]
            end = data.index(b"\0", off + nameoff)
            name = data[off + nameoff:end].decode("utf-8", "replace")
            if name.rsplit("/", 1)[-1] == libname:
                packed = (parts[0] << 16) | (parts[1] << 8) | parts[2]
                struct.pack_into("<I", data, off + 16, packed)
                open(path, "wb").write(data)
                return
        off += size

    sys.exit("%s: %s is not linked" % (path, libname))


if __name__ == "__main__":
    main()
