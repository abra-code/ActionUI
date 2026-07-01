#!/usr/bin/env bash
#
# Generate TemperatureConverter.xcodeproj from project.yml using XcodeGen.
# The generated project is committed so others can build without XcodeGen;
# rerun this only after editing project.yml.
#

HERE="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "$HERE" ]; then
  echo "error: could not resolve the script directory" >&2
  exit 1
fi
cd "$HERE"
if [ $? -ne 0 ]; then
  echo "error: could not cd to $HERE" >&2
  exit 1
fi

XCODEGEN="$(command -v xcodegen)"
if [ -z "$XCODEGEN" ]; then
  echo "XcodeGen not found. Install it with:  brew install xcodegen" >&2
  exit 1
fi

"$XCODEGEN" generate
if [ $? -ne 0 ]; then
  echo "error: 'xcodegen generate' failed" >&2
  exit 1
fi

echo "Generated $HERE/TemperatureConverter.xcodeproj"
