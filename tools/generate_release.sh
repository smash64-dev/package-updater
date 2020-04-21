#!/bin/bash
# generate_release.sh

SELF_NAME="package-updater"

SELF_DIR="$(dirname "$(readlink -f "$0")")"
BASE_DIR="$(dirname "$SELF_DIR")"
BUILD_DIR="${BASE_DIR}/build"

"${BASE_DIR}/build.bat"

echo ""
echo "- Running git archive"
git archive --format=zip --output="${BUILD_DIR}/${SELF_NAME}.zip" HEAD
echo "- Creating sha1sum.txt"
(cd "$BUILD_DIR" && sha1sum "${SELF_NAME}.zip" > sha1sum.txt)
