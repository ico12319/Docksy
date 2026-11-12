#!/bin/zsh
set -eu
cd "${0:A:h}"
app="dist/Docksy.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" .build/Gopher.iconset .build/module-cache
xcrun swiftc -module-cache-path .build/module-cache -target arm64-apple-macos13.0 \
    Sources/Sessions.swift Sources/Geometry.swift Sources/Configuration.swift Sources/DatabaseForward.swift Sources/FavouriteLinks.swift Sources/MascotChoice.swift Sources/main.swift -o "$app/Contents/MacOS/Docksy"
cp assets/Info.plist "$app/Contents/Info.plist"
cp assets/gopher.png assets/cat.png assets/dog.png assets/Terminal.applescript assets/iTerm.applescript "$app/Contents/Resources/"
cp examples/config.json "$app/Contents/Resources/config.example.json"
cp LICENSE NOTICE.md "$app/Contents/Resources/"
xcrun swift -module-cache-path .build/module-cache make-icon.swift assets/gopher.png .build/Gopher.iconset
iconutil -c icns .build/Gopher.iconset -o "$app/Contents/Resources/Gopher.icns"
# Keep the bundle identifier stable to preserve existing user preferences.
codesign --force --sign - --identifier local.usrv.gopher "$app"
printf 'Built: %s/%s\n' "$PWD" "$app"
