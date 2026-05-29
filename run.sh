#!/bin/sh
set -e

cd "$(dirname "$0")"

echo "Building PieSwitcher..."
xcodebuild -project PieSwitcher.xcodeproj -scheme PieSwitcher -configuration Debug -derivedDataPath build build

echo "Stopping any running instance..."
pkill -x PieSwitcher 2>/dev/null || true

echo "Launching PieSwitcher..."
open build/Build/Products/Debug/PieSwitcher.app

sleep 1
if pgrep -x PieSwitcher >/dev/null; then
  echo "PieSwitcher is running (PID $(pgrep -x PieSwitcher))"
else
  echo "PieSwitcher failed to launch" >&2
  exit 1
fi
