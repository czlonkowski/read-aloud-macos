#!/usr/bin/env bash
# Drop the latest Debug build of Read Aloud into /Applications and re-register it.
# Mirrors the personal reinstall pattern Romuald uses for MeetingTranscriber.

set -euo pipefail

APP_NAME="ReadAloud.app"
DERIVED_BASE="${HOME}/Library/Developer/Xcode/DerivedData"

BUILD_PATH="$(find "${DERIVED_BASE}" -type d -name "${APP_NAME}" -path "*/Build/Products/Debug/*" -print -quit 2>/dev/null)"

if [[ -z "${BUILD_PATH}" ]]; then
    echo "Could not find a Debug build of ${APP_NAME} in DerivedData." >&2
    echo "Build the app once from Xcode (⌘B) and re-run this script." >&2
    exit 1
fi

echo "==> Found build: ${BUILD_PATH}"

osascript -e "do shell script \"rm -rf /Applications/${APP_NAME} && cp -R '${BUILD_PATH}' /Applications/ && /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/${APP_NAME}\" with administrator privileges"

echo "==> Installed /Applications/${APP_NAME}"
