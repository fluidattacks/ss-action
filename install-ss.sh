#!/usr/bin/env bash
set -euo pipefail

# Installs the ss binary into a runner-local directory (no sudo) and puts it on PATH.
INSTALL_DIR="${RUNNER_TEMP}/ss-bin"
mkdir -p "${INSTALL_DIR}"

curl -fsSL https://public.fluidattacks.com/ss/install.sh | INSTALL_DIR="${INSTALL_DIR}" sh

echo "${INSTALL_DIR}" >> "${GITHUB_PATH}"
"${INSTALL_DIR}/ss" --version
