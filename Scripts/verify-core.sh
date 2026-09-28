#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"
mkdir -p build
swiftc -O -parse-as-library \
    Sources/TuneFlick/SwipeDirection.swift Sources/TuneFlick/ScrollGestureRouter.swift \
    Sources/TuneFlick/GesturePreferences.swift Sources/TuneFlick/GestureActivationPolicy.swift \
    Sources/TuneFlick/PlayerDetector.swift Sources/TuneFlick/MediaControlProcess.swift \
    Sources/TuneFlick/MediaController.swift Scripts/verify-core.swift -o build/verify-core
build/verify-core
