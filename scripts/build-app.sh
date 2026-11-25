#!/bin/zsh
set -eu
cd "${0:A:h}/.."
configuration="${1:-debug}"
swift build -c "$configuration"
app=".build/Act.app"
# Rebuild the generated bundle so removed resources cannot enter a download.
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources"
binary_directory="$(swift build -c "$configuration" --show-bin-path)"
cp "$binary_directory/Act" "$app/Contents/MacOS/Act"
zsh scripts/build-cli.sh
cp .build/act "$app/Contents/Helpers/act"
/usr/bin/codesign --force --sign - "$app/Contents/Helpers/act"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/Act.icns "$app/Contents/Resources/Act.icns"
for localisation in Resources/*.lproj; do
    ditto "$localisation" "$app/Contents/Resources/${localisation:t}"
done
# SwiftPM's generated resource accessor searches the app resource directory first.
ditto "$binary_directory/Act_ActCore.bundle" "$app/Contents/Resources/Act_ActCore.bundle"
/usr/bin/codesign --force --sign - "$app"
print -r -- "$PWD/$app"
