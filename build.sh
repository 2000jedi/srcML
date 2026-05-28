#!/usr/bin/env nix-shell
#!nix-shell -i bash -p cmake ninja pkg-config curl libxml2 libxslt libarchive openjdk antlr2 boost
set -euo pipefail

BUILD_DIR="${BUILD_DIR:-build}"
cmake -S . -B "$BUILD_DIR" -G Ninja \
  -DBUILD_LIBSRCML_TESTS=ON \
  -DBUILD_CLIENT_TESTS=OFF \
  -DBUILD_PARSER_TESTS=OFF \
  -DCMAKE_BUILD_TYPE=Debug
cmake --build "$BUILD_DIR" -- "$@"
