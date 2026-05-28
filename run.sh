#!/bin/sh
set -e

cd "$(dirname "$0")"

echo "Building Bringr..."
xcodebuild -project Bringr.xcodeproj -scheme Bringr -configuration Debug -derivedDataPath build build

echo "Stopping any running instance..."
pkill -x Bringr 2>/dev/null || true

echo "Launching Bringr..."
open build/Build/Products/Debug/Bringr.app

sleep 1
if pgrep -x Bringr >/dev/null; then
  echo "Bringr is running (PID $(pgrep -x Bringr))"
else
  echo "Bringr failed to launch" >&2
  exit 1
fi
