#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p .build/module-cache
xcrun swiftc -module-cache-path .build/module-cache Sources/Sessions.swift Sources/Geometry.swift Sources/Configuration.swift Sources/DatabaseForward.swift Sources/FavouriteLinks.swift Sources/MascotChoice.swift Tests/main.swift -o .build/session-unit-tests
.build/session-unit-tests
