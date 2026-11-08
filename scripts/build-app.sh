#!/bin/bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$project_root"

# Forward SwiftPM options, such as -c release or a custom cache path.
swift build "$@"
binary_directory="$(swift build "$@" --show-bin-path)"
app_directory="$project_root/.build/NewZMud.app"
mkdir -p "$app_directory/Contents/MacOS"
cp "$binary_directory/NewZMud" "$app_directory/Contents/MacOS/NewZMud"
cp Support/Info.plist "$app_directory/Contents/Info.plist"
printf 'App ready: %s\n' "$app_directory"
