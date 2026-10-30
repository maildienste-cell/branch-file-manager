#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
if [[ "$(uname -m)" != "arm64" ]]; then
  print -u2 "This release builds for Apple Silicon (arm64)."; exit 1
fi
sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
if [[ "${sdk_version%%.*}" -lt 26 ]]; then
  print -u2 "Xcode 26 or newer with the macOS 26 SDK is required."; exit 1
fi
build_area="$(mktemp -d -t branch-build)"
trap 'rm -rf "$build_area"' EXIT
app_path="$build_area/Branch.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" build
cp Resources/Info.plist "$app_path/Contents/Info.plist"
cp Resources/AppIcon.icns "$app_path/Contents/Resources/AppIcon.icns"
xcrun swiftc -target arm64-apple-macos14.0 \
  -debug-prefix-map "$PWD"=. \
  Source/main.swift Source/Transfers.swift Source/Workspace.swift Source/Preview.swift \
  Source/Desktop.swift Source/Explorer.swift Source/Tests.swift Source/Robot.swift \
  Source/TransferSpeed.swift Source/FileSearch.swift Source/FileChat.swift \
  -o "$app_path/Contents/MacOS/Branch" \
  -framework AppKit -framework Quartz -framework PDFKit \
  -Xlinker -weak_framework -Xlinker FoundationModels
xattr -cr "$app_path"
codesign --force --sign - "$app_path"
codesign --verify --deep --strict "$app_path"
"$app_path/Contents/MacOS/Branch" --self-test
ditto --norsrc "$app_path" build/Branch.app
print "Built and tested: build/Branch.app"
