```
  ___                   __  __ __     __ ____  ____  _  __
 / _ \ _ __   ___ _ __ |  \/  |\ \   / // ___||  _ \| |/ /
| | | | '_ \ / _ \ '_ \| |\/| | \ \ / / \___ \| | | | ' /
| |_| | |_) |  __/ | | | |  | |  \ V /   ___) | |_| | . \
 \___/| .__/ \___|_| |_|_|  |_|   \_/   |____/|____/|_|\_\
      |_|
```

Build scripts and CI for the OpenMV SDK. Produces platform-specific SDK bundles containing all tools needed to build OpenMV firmware.

## Platforms

| Platform | Runner | Status |
|---|---|---|
| Linux x86_64 | `ubuntu-24.04` | Supported |
| macOS arm64 | `macos-latest` | Supported |
| Windows x86_64 | `windows-latest` (MSYS2) | Supported |

## SDK Contents

| Component | Description |
|---|---|
| `gcc/` | ARM GNU Toolchain 14.3 |
| `llvm/` | LLVM Embedded Toolchain for Arm 18.1.3 |
| `cmake/` | CMake 3.30.2 |
| `make/` | GNU Make 4.4.1 (built from source) |
| `python/` | Python 3.12 + packages (uv, flake8, vela, spsdk, etc.) |
| `stedgeai/` | ST Edge AI 3.0 |
| `stcubeprog/` | ST CubeProgrammer 2.21.0 (Linux/macOS only) |
| `bin/` | dfu-util, uncrustify, pv (Linux/macOS only) |

## Usage

```sh
SDK_VERSION=1.4.0 ./tools/build.sh
SDK_VERSION=1.4.0 ./tools/package.sh
```

## Scripts

- `tools/build.sh` - Downloads, extracts, and builds all SDK components.
- `tools/package.sh` - Strips STEdgeAI and compresses the SDK into a `.tar.xz` archive.
- `tools/downloads.cfg` - Download URLs and SHA-256 checksums for all components.

## License

MIT - see [LICENSE](LICENSE).
