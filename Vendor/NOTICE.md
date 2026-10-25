# Bundled USB library

`libusb-1.0.dylib` is libusb 1.0.30 for Apple silicon, obtained from the `libusb-package` 1.0.30.0
macOS wheel. The libusb library is licensed under GNU LGPL version 2.1; the complete license text
is in `LGPL-2.1.txt`. The app loads the shared library dynamically from its Resources folder, so
the library can be replaced independently.

Corresponding upstream source: https://github.com/libusb/libusb/tree/v1.0.30
The separate `libusb-package` Python wrapper is not included in Keyflow.
