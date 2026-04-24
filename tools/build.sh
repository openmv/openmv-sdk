#!/bin/bash
# This file is part of the OpenMV project.
#
# Copyright (C) 2026 OpenMV, LLC.
#
# This work is licensed under the MIT license, see the file LICENSE for details.
#
# Builds a platform-specific OpenMV SDK.
# The SDK version is read from the SDK_VERSION environment variable.
#
# Usage: SDK_VERSION=1.4.0 ./tools/build.sh

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
TMPDIR_SDK="${BUILD_DIR}/tmp"
NPROC=$(nproc 2>/dev/null || sysctl -n hw.ncpu)

########################################################################################
# Load download URLs and checksums
source "${SCRIPT_DIR}/downloads.cfg"

# Platform key for variable lookups (e.g. linux_x86_64, darwin_arm64)
PLAT_KEY="${SDK_PLATFORM//-/_}"

# Resolve per-platform variables using indirect expansion
resolve_var() {
    local prefix="$1" suffix="$2"
    local varname="${prefix}_${suffix}_${PLAT_KEY}"
    # Fall back to platform-independent variable
    if [ -z "${!varname:-}" ]; then
        varname="${prefix}_${suffix}"
    fi
    echo "${!varname}"
}

########################################################################################
# Helper functions
download() {
    local url="$1" dest="$2"
    echo "  Downloading $(basename "${url}")..."
    if [ "${CI:-}" = "true" ]; then
        curl -fsSL -o "${dest}" "${url}"
    else
        curl -fL --progress-bar -o "${dest}" "${url}"
    fi
}

verify_sha256() {
    local file="$1" expected="$2"
    echo "  Verifying $(basename "${file}")..."
    if command -v sha256sum &>/dev/null; then
        echo "${expected}  ${file}" | sha256sum -c -
    else
        echo "${expected}  ${file}" | shasum -a 256 -c -
    fi
}

download_component() {
    local prefix="$1"
    local dest url sha

    dest="$(resolve_var "${prefix}" DEST)"
    url="$(resolve_var "${prefix}" URL)"
    sha="$(resolve_var "${prefix}" SHA)"

    if [ -z "${url}" ] || [ -z "${sha}" ]; then
        echo "Error: missing URL or SHA for ${prefix} on ${SDK_PLATFORM}"
        exit 1
    fi

    if [[ -f "${TMPDIR_SDK}/${dest}" ]]; then
        echo "  Skipping ${dest} (already downloaded)"
    else
        download "${url}" "${TMPDIR_SDK}/${dest}"
        verify_sha256 "${TMPDIR_SDK}/${dest}" "${sha}"
    fi
}

extract_dmg() {
    local dmg="$1" dest="$2" mountpoint="$3"
    mkdir -p "${mountpoint}"
    hdiutil attach "${dmg}" -nobrowse -quiet -mountpoint "${mountpoint}"
    local root
    root=$(find "${mountpoint}" -maxdepth 1 -mindepth 1 -type d | grep -v Applications | head -1)
    cp -r "${root}/." "${dest}/"
    hdiutil detach "${mountpoint}" -quiet
}

extract_zip() {
    local zipfile="$1" destdir="$2"
    local tmpdir="${TMPDIR_SDK}/_zip_extract"
    rm -rf "${tmpdir}"
    mkdir -p "${tmpdir}"
    unzip -q "${zipfile}" -d "${tmpdir}"
    local topdir
    topdir=$(find "${tmpdir}" -maxdepth 1 -mindepth 1 -type d | head -1)
    cp -a "${topdir}/." "${destdir}/"
    rm -rf "${tmpdir}"
}

run_installer() {
    local installer="$1" root="$2"
    shift 2
    local args=(--root "${root}" --accept-licenses --accept-messages --confirm-command install "$@")
    if [[ "${installer}" == *.dmg ]]; then
        local mountpoint="${TMPDIR_SDK}/installer_mount"
        mkdir -p "${mountpoint}"
        hdiutil attach "${installer}" -nobrowse -quiet -mountpoint "${mountpoint}"
        local app
        app=$(find "${mountpoint}" -maxdepth 1 -name "*.app" | head -1)
        "${app}/Contents/MacOS/$(basename "${app}" .app)" "${args[@]}"
        hdiutil detach "${mountpoint}" -quiet
    else
        chmod +x "${installer}"
        "${installer}" "${args[@]}"
    fi
}

########################################################################################
# Build
echo "Building ${SDK_NAME}..."
rm -rf "${SDK_STAGE}"
mkdir -p "${SDK_STAGE}" "${BUILD_DIR}" "${TMPDIR_SDK}"

# Download and verify all components
echo ""
COMPONENTS="GCC LLVM CMAKE STEDGEAI PYTHON MAKE UNCRUSTIFY"
if [[ "${SDK_PLATFORM}" != windows-* ]]; then
    COMPONENTS="${COMPONENTS} CUBEPROG PV"
fi
for component in ${COMPONENTS}; do
    download_component "${component}"
done

# Extract: GCC
echo "Extracting GCC..."
mkdir -p "${SDK_STAGE}/gcc"
if [[ "${SDK_PLATFORM}" == windows-* ]]; then
    extract_zip "${TMPDIR_SDK}/$(resolve_var GCC DEST)" "${SDK_STAGE}/gcc"
else
    tar --strip-components=1 -Jxf "${TMPDIR_SDK}/$(resolve_var GCC DEST)" -C "${SDK_STAGE}/gcc"
fi

# Extract: LLVM
echo "Extracting LLVM..."
mkdir -p "${SDK_STAGE}/llvm"
if [[ "${SDK_PLATFORM}" == windows-* ]]; then
    extract_zip "${TMPDIR_SDK}/$(resolve_var LLVM DEST)" "${SDK_STAGE}/llvm"
elif [[ "${SDK_PLATFORM}" == darwin-* ]]; then
    extract_dmg "${TMPDIR_SDK}/$(resolve_var LLVM DEST)" "${SDK_STAGE}/llvm" "${TMPDIR_SDK}/llvm_mount"
else
    tar --strip-components=1 -Jxf "${TMPDIR_SDK}/$(resolve_var LLVM DEST)" -C "${SDK_STAGE}/llvm"
fi

# Build: GNU Make from source
echo "Building GNU Make..."
MAKE_SRC="${TMPDIR_SDK}/make_src"
if [ ! -f "${MAKE_SRC}/make" ]; then
    mkdir -p "${MAKE_SRC}"
    tar --strip-components=1 -zxf "${TMPDIR_SDK}/$(resolve_var MAKE DEST)" -C "${MAKE_SRC}"
    MAKE_CFLAGS="-w"
    if [[ "${SDK_PLATFORM}" == windows-* ]]; then
        MAKE_CFLAGS="-w -std=gnu89"
    fi
    (cd "${MAKE_SRC}" && ./configure --quiet --without-guile CFLAGS="${MAKE_CFLAGS}" && make -j${NPROC} --quiet)
fi
mkdir -p "${SDK_STAGE}/make"
cp "${MAKE_SRC}/make" "${SDK_STAGE}/make/make"

# Extract: CMake
echo "Extracting CMake..."
mkdir -p "${SDK_STAGE}/cmake"
if [[ "${SDK_PLATFORM}" == windows-* ]]; then
    extract_zip "${TMPDIR_SDK}/$(resolve_var CMAKE DEST)" "${SDK_STAGE}/cmake"
elif [[ "${SDK_PLATFORM}" == darwin-* ]]; then
    tar --strip-components=3 -zxf "${TMPDIR_SDK}/$(resolve_var CMAKE DEST)" -C "${SDK_STAGE}/cmake"
else
    tar --strip-components=1 -zxf "${TMPDIR_SDK}/$(resolve_var CMAKE DEST)" -C "${SDK_STAGE}/cmake"
fi

# Install: STEdgeAI (stripping is done in package.sh)
echo "Installing STEdgeAI..."
STEDGEAI_ROOT="${TMPDIR_SDK}/STEdgeAI"
if [ ! -d "${STEDGEAI_ROOT}/${STEDGEAI_VERSION}" ]; then
    # shellcheck disable=SC2086
    run_installer "${TMPDIR_SDK}/$(resolve_var STEDGEAI DEST)" "${STEDGEAI_ROOT}" ${STEDGEAI_COMPONENTS}
fi
cp -a "${STEDGEAI_ROOT}/${STEDGEAI_VERSION}" "${SDK_STAGE}/stedgeai"

# Build: dfu-util from source
echo "Building dfu-util..."
DFU_BUILD="${TMPDIR_SDK}/dfu_build"
mkdir -p "${DFU_BUILD}"

# Build libusb statically (Unix only; Windows uses MSYS2 system libusb)
if [[ "${SDK_PLATFORM}" != windows-* ]]; then
    if [ ! -f "${DFU_BUILD}/libusb-install/lib/libusb-1.0.a" ]; then
        echo "  Building libusb ${LIBUSB_VERSION}..."
        curl -fL -o "${DFU_BUILD}/libusb.tar.bz2" \
            "https://github.com/libusb/libusb/releases/download/v${LIBUSB_VERSION}/libusb-${LIBUSB_VERSION}.tar.bz2"
        tar xf "${DFU_BUILD}/libusb.tar.bz2" -C "${DFU_BUILD}"
        (
            cd "${DFU_BUILD}/libusb-${LIBUSB_VERSION}"
            CONFIGURE_ARGS="--prefix=${DFU_BUILD}/libusb-install --enable-static --disable-shared"
            if [[ "${SDK_PLATFORM}" == linux-* ]]; then
                CONFIGURE_ARGS="${CONFIGURE_ARGS} --disable-udev"
            fi
            ./configure ${CONFIGURE_ARGS}
            make -j${NPROC}
            make install
        )
    fi
fi

# Build dfu-util
if [ ! -f "${DFU_BUILD}/dfu-util-src/src/dfu-util" ]; then
    echo "  Building dfu-util..."
    git clone "${DFU_UTIL_REPO}" "${DFU_BUILD}/dfu-util-src"
    (
        cd "${DFU_BUILD}/dfu-util-src"
        git checkout "${DFU_UTIL_COMMIT}"
        ./autogen.sh

        if [[ "${SDK_PLATFORM}" == windows-* ]]; then
            ./configure LDFLAGS="-static" PKG_CONFIG="pkg-config --static"
        elif [[ "${SDK_PLATFORM}" == darwin-* ]]; then
            PKG_CONFIG_ARGS="PKG_CONFIG_PATH=${DFU_BUILD}/libusb-install/lib/pkgconfig"
            USB_LIBS="${DFU_BUILD}/libusb-install/lib/libusb-1.0.a -framework IOKit -framework CoreFoundation -framework Security"
            ./configure ${PKG_CONFIG_ARGS} USB_LIBS="${USB_LIBS}"
        else
            PKG_CONFIG_ARGS="PKG_CONFIG_PATH=${DFU_BUILD}/libusb-install/lib/pkgconfig"
            ./configure ${PKG_CONFIG_ARGS}
        fi

        make -C src -j${NPROC}
    )
fi

mkdir -p "${SDK_STAGE}/bin"
cp "${DFU_BUILD}/dfu-util-src/src/dfu-util" "${SDK_STAGE}/bin/dfu-util"
chmod +x "${SDK_STAGE}/bin/dfu-util"

# Build: pv from source (Unix only, uses POSIX terminal I/O)
if [[ "${SDK_PLATFORM}" != windows-* ]]; then
    echo "Building pv..."
    PV_BUILD="${TMPDIR_SDK}/pv_build"
    if [ ! -f "${PV_BUILD}/pv" ]; then
        mkdir -p "${PV_BUILD}"
        tar --strip-components=1 -zxf "${TMPDIR_SDK}/$(resolve_var PV DEST)" -C "${PV_BUILD}"
        (cd "${PV_BUILD}" && ./configure --quiet && make -j${NPROC} --quiet)
    fi
    cp "${PV_BUILD}/pv" "${SDK_STAGE}/bin/pv"
    chmod +x "${SDK_STAGE}/bin/pv"
fi

# Build: Uncrustify from source
echo "Building Uncrustify..."
UNCRUSTIFY_BUILD="${TMPDIR_SDK}/uncrustify_build"
if [ ! -f "${UNCRUSTIFY_BUILD}/build/uncrustify" ]; then
    mkdir -p "${UNCRUSTIFY_BUILD}"
    tar --strip-components=1 -zxf "${TMPDIR_SDK}/$(resolve_var UNCRUSTIFY DEST)" -C "${UNCRUSTIFY_BUILD}"
    mkdir -p "${UNCRUSTIFY_BUILD}/build"
    (
        cd "${UNCRUSTIFY_BUILD}/build"
        "${SDK_STAGE}/cmake/bin/cmake" .. -DCMAKE_BUILD_TYPE=Release
        "${SDK_STAGE}/cmake/bin/cmake" --build . --parallel ${NPROC} --config Release
    )
fi
if [[ "${SDK_PLATFORM}" == windows-* ]]; then
    cp "${UNCRUSTIFY_BUILD}/build/Release/uncrustify.exe" "${SDK_STAGE}/bin/uncrustify.exe"
else
    cp "${UNCRUSTIFY_BUILD}/build/uncrustify" "${SDK_STAGE}/bin/uncrustify"
fi
chmod +x "${SDK_STAGE}/bin/uncrustify"

# Extract: ST CubeProgrammer (not available on Windows)
if [[ "${SDK_PLATFORM}" != windows-* ]]; then
    echo "Extracting ST CubeProgrammer..."
    mkdir -p "${SDK_STAGE}/stcubeprog"
    tar --strip-components=1 -zxf "${TMPDIR_SDK}/$(resolve_var CUBEPROG DEST)" -C "${SDK_STAGE}/stcubeprog"
fi

# Extract: Python + install packages
echo "Extracting Python..."
mkdir -p "${SDK_STAGE}/python"
tar --strip-components=1 -zxf "${TMPDIR_SDK}/$(resolve_var PYTHON DEST)" -C "${SDK_STAGE}/python"
if [[ "${SDK_PLATFORM}" == windows-* ]]; then
    PYTHON="${SDK_STAGE}/python/python.exe"
    UV="${SDK_STAGE}/python/Scripts/uv.exe"
    PYTHON_HOME="${SDK_STAGE}/python"
else
    PYTHON="${SDK_STAGE}/python/bin/python3"
    UV="${SDK_STAGE}/python/bin/uv"
    PYTHON_HOME="${SDK_STAGE}/python/bin"
fi
echo "Installing Python packages..."
"${PYTHON}" -m pip install uv --quiet
# Create a temporary pyvenv.cfg so uv generates relocatable entry-point scripts
VENV="${SDK_STAGE}/python"
if [[ "${SDK_PLATFORM}" == windows-* ]]; then
    printf 'home = %s\nrelocatable = true\n' "$(cygpath -w "${PYTHON_HOME}")" > "${SDK_STAGE}/python/pyvenv.cfg"
    VENV="$(cygpath -w "${VENV}")"
else
    printf 'home = %s\nrelocatable = true\n' "${PYTHON_HOME}" > "${SDK_STAGE}/python/pyvenv.cfg"
fi
VIRTUAL_ENV="${VENV}" "${UV}" pip install --python "${PYTHON}" \
    flake8==6.0.0 \
    pytest==7.4.0 \
    ethos-u-vela==4.2.0 \
    tabulate==0.9.0 \
    cryptography==46.0.7 \
    pyelftools==0.27 \
    colorama==0.4.6 \
    mpremote==1.27.0 \
    spsdk==3.8.0 \
    "pyserial @ git+https://github.com/pyserial/pyserial.git@911a0b8c110f3d3513bab67e64d95d1310517454"
rm "${SDK_STAGE}/python/pyvenv.cfg"

# Write version file
echo ""
echo "${SDK_VERSION}" > "${SDK_STAGE}/sdk.version"

echo "Build complete."
echo "  ${SDK_STAGE}"
