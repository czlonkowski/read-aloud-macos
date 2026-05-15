#!/usr/bin/env bash
# One-shot: regenerate Xcode project → build Debug → install to /Applications → launch.
# Mirrors the personal install flow Romuald uses for MeetingTranscriber, but
# bundles every step so it's a single CLI invocation:
#
#   ./scripts/reinstall.sh
#
# Pass --no-open to skip the final launch.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ReadAloud.app"
PROJECT="${REPO_ROOT}/ReadAloud.xcodeproj"
SCHEME="ReadAloud"
DERIVED="${REPO_ROOT}/build"
PRODUCT_PATH="${DERIVED}/Build/Products/Debug/${APP_NAME}"

OPEN_AFTER=1
for arg in "$@"; do
    case "${arg}" in
        --no-open) OPEN_AFTER=0 ;;
        *) echo "Unknown flag: ${arg}" >&2; exit 2 ;;
    esac
done

cd "${REPO_ROOT}"

if [[ ! -d "${PROJECT}" ]] || [[ "${REPO_ROOT}/project.yml" -nt "${PROJECT}/project.pbxproj" ]]; then
    if ! command -v xcodegen >/dev/null 2>&1; then
        echo "xcodegen not found. Install with: brew install xcodegen" >&2
        exit 1
    fi
    echo "==> Regenerating Xcode project"
    xcodegen generate
fi

echo "==> Building ${SCHEME} (Debug)"
xcodebuild \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "${DERIVED}" \
    -quiet \
    build

if [[ ! -d "${PRODUCT_PATH}" ]]; then
    echo "Build succeeded but ${PRODUCT_PATH} is missing." >&2
    exit 1
fi

echo "==> Installing to /Applications (you'll be prompted for your password)"
osascript -e "do shell script \"rm -rf /Applications/${APP_NAME} && cp -R '${PRODUCT_PATH}' /Applications/ && /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/${APP_NAME}\" with administrator privileges"

echo "==> Installed /Applications/${APP_NAME}"

if (( OPEN_AFTER )); then
    # If a previous instance is still running, quit it cleanly so the new
    # binary takes over (avoids "translocation" / stale-binary surprises).
    osascript -e 'tell application "ReadAloud" to quit' 2>/dev/null || true
    sleep 0.5
    open "/Applications/${APP_NAME}"
    echo "==> Launched. Grant Accessibility permission when prompted:"
    echo "    System Settings ▸ Privacy & Security ▸ Accessibility ▸ ReadAloud"
fi
