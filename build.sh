#!/bin/sh
set -eu
cd "$(dirname "$0")"
APP="build/Keyflow Status.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
iconutil -c icns Resources/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
swift build --configuration release --build-path build/swiftpm
cp build/swiftpm/release/KeyflowStatus "$APP/Contents/MacOS/KeyflowStatus"
ditto Resources/Profiles "$APP/Contents/Resources/Profiles"
cp Vendor/libusb-1.0.dylib "$APP/Contents/Resources/libusb-1.0.dylib"
echo "Built $APP"
