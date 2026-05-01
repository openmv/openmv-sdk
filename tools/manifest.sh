#!/bin/bash
# This file is part of the OpenMV project.
#
# Copyright (C) 2026 OpenMV, LLC.
#
# This work is licensed under the MIT license, see the file LICENSE for details.
#
# Generates tools.json from a directory of tools-${PLAT}.tar.xz archives
# (with .sha256 sidecars). Used by the upload step in sdk.yml when
# BUILD_TARGET=tools.
#
# Usage: SDK_VERSION=1.0.0 ./tools/manifest.sh <artifacts_dir> <output_file>

set -euo pipefail

: "${SDK_VERSION:?SDK_VERSION environment variable is required}"
DIR="${1:?artifacts dir required}"
OUT="${2:?output file required}"
BASE_URL="https://download.openmv.io/studio"

{
    printf '{\n  "version": "%s",\n  "platforms": {\n' "${SDK_VERSION}"
    first=true
    for f in "${DIR}"/tools-*.tar.xz; do
        [ -e "$f" ] || continue
        base="$(basename "$f")"
        plat="${base#tools-}"
        plat="${plat%.tar.xz}"
        sha="$(awk '{print $1}' "${f}.sha256")"
        size="$(wc -c < "$f" | tr -d ' ')"
        [ "$first" = true ] || printf ',\n'
        first=false
        printf '    "%s": {\n      "url": "%s/%s",\n      "sha256": "%s",\n      "size": %s\n    }' \
            "$plat" "$BASE_URL" "$base" "$sha" "$size"
    done
    printf '\n  }\n}\n'
} > "${OUT}"

echo "Wrote ${OUT}"
