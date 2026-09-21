#!/bin/sh
set -eu
cd "$(dirname "$0")"
swift format lint --strict --recursive App Sources Tests Package.swift
swift test
xcodebuild -quiet -project AttentionLog.xcodeproj -scheme AttentionLog \
  -configuration Debug -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
