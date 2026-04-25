#!/bin/bash
# This file is part of the OpenMV project.
#
# Copyright (C) 2026 OpenMV, LLC.
#
# This work is licensed under the MIT license, see the file LICENSE for details.
#
# Strips the STEdgeAI component and packages the SDK into a tar.xz archive.
# The SDK version is read from the SDK_VERSION environment variable.
#
# Usage: SDK_VERSION=1.4.0 ./tools/package.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

########################################################################################
# Configuration
: "${SDK_VERSION:?SDK_VERSION environment variable is required}"
case "$(uname -s)" in
    MSYS*|MINGW*) SDK_PLATFORM="windows-x86_64" ;;
    *)            SDK_PLATFORM="$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)" ;;
esac
SDK_NAME="openmv-sdk-${SDK_VERSION}-${SDK_PLATFORM}"
BUILD_DIR="${REPO_DIR}/sdk"
SDK_STAGE="${BUILD_DIR}/${SDK_NAME}"
NPROC=$(nproc 2>/dev/null || sysctl -n hw.ncpu)

if [ ! -d "${SDK_STAGE}" ]; then
    echo "Error: ${SDK_STAGE} does not exist. Run build.sh first."
    exit 1
fi

########################################################################################
# Strip STEdgeAI
STEDGEAI="${SDK_STAGE}/stedgeai"

if [ ! -d "${STEDGEAI}" ]; then
    echo "Error: ${STEDGEAI} does not exist."
    exit 1
fi

# Detect platform
case "$(uname -s)-$(uname -m)" in
    Linux-x86_64)   KEEP_UTIL="linux"   ;;
    Darwin-arm64)    KEEP_UTIL="macarm"  ;;
    Darwin-x86_64)   KEEP_UTIL="mac"     ;;
    MSYS*|MINGW*)    KEEP_UTIL="windows" ;;
    *)  echo "Unsupported platform: $(uname -s)-$(uname -m)"; exit 1 ;;
esac

UTIL="${STEDGEAI}/Utilities/${KEEP_UTIL}"
if [[ "${KEEP_UTIL}" == "windows" ]]; then
    PYLIB="${UTIL}/Lib"
    SITE="${PYLIB}/site-packages"
else
    PYLIB="${UTIL}/lib"
    SITE="${PYLIB}/python3.9/site-packages"
fi

echo "Stripping STEdgeAI (keeping Utilities/${KEEP_UTIL})..."

# Remove other platform utilities
for d in "${STEDGEAI}/Utilities"/*/; do
    name="$(basename "$d")"
    if [ "$name" != "$KEEP_UTIL" ] && [ "$name" != "configs" ] && [ "$name" != "etc" ]; then
        rm -rf "$d"
    fi
done

# Remove other platform libs in scripts/
for d in "${STEDGEAI}/scripts"/*/lib/*/; do
    name="$(basename "$d")"
    if [ "$name" != "$KEEP_UTIL" ]; then
        rm -rf "$d"
    fi
done

# Remove mlc_tool (Qt GUI, not needed)
rm -rf "${STEDGEAI}/Utilities/${KEEP_UTIL}/mlc_tool"

# Remove docs, projects, unused middlewares
rm -rf "${STEDGEAI}/Documentation"
rm -rf "${STEDGEAI}/Projects"
rm -rf "${STEDGEAI}/Middlewares/ST/usbx"
rm -rf "${STEDGEAI}/Middlewares/ST/threadx"
rm -rf "${STEDGEAI}/Middlewares/ST/FreeRTOS"

# TensorFlow: C++ headers
rm -rf "${SITE}/tensorflow/include"

# Python stdlib cruft
for d in test idlelib ensurepip tkinter turtledemo; do
    rm -rf "${PYLIB}/python3.9/$d"
done
rm -rf "${PYLIB}/python3.9/config-3.9-darwin"
rm -rf "${PYLIB}/python3.9/config-3.9-x86_64-linux-gnu"
rm -f  "${PYLIB}/python3.9/turtle.py"

# Tcl/Tk
for d in tcl8.6 tk8.6 tcl8 itcl4.2.2 tdbc1.1.3 tdbcodbc1.1.3 tdbcpostgres1.1.3 tdbcmysql1.1.3 thread2.8.7; do
    rm -rf "${PYLIB}/$d"
done

# Unnecessary Python packages
for d in tensorboard pygments; do
    rm -rf "${SITE}/$d"
done

# Test dirs in site-packages
find "${SITE}" -maxdepth 2 -name "tests" -type d -exec rm -rf {} + 2>/dev/null || true
find "${SITE}" -maxdepth 2 -name "test" -type d -exec rm -rf {} + 2>/dev/null || true

# Remove .DS_Store files
find "${SDK_STAGE}" -name ".DS_Store" -delete 2>/dev/null || true

# Remove __pycache__ on Windows to avoid MAX_PATH issues with NSIS
if [[ "${KEEP_UTIL}" == "windows" ]]; then
    echo "Removing __pycache__ directories..."
    find "${SITE}" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
else
    # Recompile .pyc files so embedded timestamps match the .py sources
    echo "Recompiling .pyc files..."
    STEDGE_PYTHON="${UTIL}/python"
    "${STEDGE_PYTHON}" -m compileall -q -f "${PYLIB}" 2>/dev/null || true
fi

echo "Done."

########################################################################################
# Package
echo "Packaging ${SDK_NAME}..."
cd "${BUILD_DIR}"
echo "  Creating archive..."
tar -cf - "${SDK_NAME}" | xz -3 -T${NPROC} > "${SDK_NAME}.tar.xz"
echo "  Computing checksum..."
if command -v sha256sum &>/dev/null; then
    sha256sum "${SDK_NAME}.tar.xz" > "${SDK_NAME}.tar.xz.sha256"
else
    shasum -a 256 "${SDK_NAME}.tar.xz" > "${SDK_NAME}.tar.xz.sha256"
fi
echo "Done:"
echo "  ${BUILD_DIR}/${SDK_NAME}.tar.xz"
echo "  ${BUILD_DIR}/${SDK_NAME}.tar.xz.sha256"
