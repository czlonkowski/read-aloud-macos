#!/usr/bin/env bash
# Install the Read Aloud TTS sidecar as a launchd agent.
#
# Requires `uv` (https://docs.astral.sh/uv/getting-started/installation/).
# Run from the repo root:
#
#   ./scripts/install-sidecar.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIDECAR_DIR="${REPO_ROOT}/sidecar"
SUPPORT_DIR="${HOME}/Library/Application Support/ReadAloud"
VENV_DIR="${SUPPORT_DIR}/sidecar-venv"
AGENT_LABEL="com.czlonkowski.readaloud-sidecar"
PLIST_PATH="${HOME}/Library/LaunchAgents/${AGENT_LABEL}.plist"
LOG_DIR="${SUPPORT_DIR}/logs"

if ! command -v uv >/dev/null 2>&1; then
    echo "uv not found. Install it with: brew install uv" >&2
    exit 1
fi

mkdir -p "${SUPPORT_DIR}" "${LOG_DIR}" "$(dirname "${PLIST_PATH}")"

echo "==> Creating Python environment at ${VENV_DIR}"
uv venv --python 3.12 "${VENV_DIR}"

echo "==> Installing read-aloud-tts (this downloads ~2 GB of models on first run)"
# shellcheck source=/dev/null
VIRTUAL_ENV="${VENV_DIR}" uv pip install --python "${VENV_DIR}/bin/python" -e "${SIDECAR_DIR}"

echo "==> Writing launchd plist to ${PLIST_PATH}"
cat > "${PLIST_PATH}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${AGENT_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${VENV_DIR}/bin/python</string>
        <string>-m</string>
        <string>read_aloud_tts.server</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HF_HOME</key>
        <string>${SUPPORT_DIR}/huggingface</string>
        <key>PYTORCH_ENABLE_MPS_FALLBACK</key>
        <string>1</string>
    </dict>
    <key>RunAtLoad</key>
    <false/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
        <key>Crashed</key>
        <true/>
    </dict>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/sidecar.out.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/sidecar.err.log</string>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
EOF

echo "==> Loading launchd agent"
launchctl bootout "gui/$(id -u)/${AGENT_LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "${PLIST_PATH}"

echo
echo "Sidecar installed."
echo "  Start:  launchctl kickstart -k gui/$(id -u)/${AGENT_LABEL}"
echo "  Stop:   launchctl bootout    gui/$(id -u)/${AGENT_LABEL}"
echo "  Health: curl -s http://127.0.0.1:8000/healthz"
echo "  Logs:   tail -f \"${LOG_DIR}/sidecar.err.log\""
