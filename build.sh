#!/bin/sh
set -eu
cd "$(dirname "$0")"
rm -rf wattex.app
mkdir -p wattex.app/Contents/MacOS
swiftc -O -swift-version 5 -o wattex.app/Contents/MacOS/wattex main.swift
cp Info.plist wattex.app/Contents/Info.plist
codesign --force --sign - wattex.app
