#!/bin/sh
set -eu
cd "$(dirname "$0")"
rm -rf wattex.app
mkdir -p wattex.app/Contents/MacOS
# -target matches LSMinimumSystemVersion (SMAppService needs 13); -swift-version 5 is required, Swift 6
# mode rejects the top-level globals as main-actor isolated.
swiftc -O -swift-version 5 -target arm64-apple-macos13 -o wattex.app/Contents/MacOS/wattex main.swift
cp Info.plist wattex.app/Contents/Info.plist
codesign --force --sign - wattex.app
