#!/bin/bash
# generate_release.sh

SELF_NAME="package-updater"

SELF_DIR="$(dirname "$(readlink -f "$0")")"
BASE_DIR="$(dirname "$SELF_DIR")"
BUILD_DIR="${BASE_DIR}/build"

# support building on multiple platforms
case $(uname -s) in
    [Ll]inux)   wine cmd.exe /c "${BASE_DIR}/build.bat" ;;
    *)          "${BASE_DIR}/build.bat" ;;
esac

echo ""
echo "- Running git archive"
git archive --format=zip --output="${BUILD_DIR}/${SELF_NAME}.zip" HEAD
echo "- Creating sha1sum.txt"
(cd "$BUILD_DIR" && sha1sum "${SELF_NAME}.zip" > sha1sum.txt)

exit
