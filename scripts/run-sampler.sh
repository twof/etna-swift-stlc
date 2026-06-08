#!/bin/bash
# Run the built `stlc-sampler` with the patched toolchain's runtime on the dylib
# path. ETNA's `sample` capability invokes this.
#   run-sampler.sh <property> <count>
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="${BUILD_ROOT:-/Users/fnord/Documents/OpenSourceDev/build/Ninja-RelWithDebInfoAssert}"
RT="$BUILD_ROOT/swift-macosx-arm64/lib/swift/macosx"
CONFIG="${CONFIG:-debug}"
exec env DYLD_LIBRARY_PATH="$RT" "$ROOT/.build/$CONFIG/stlc-sampler" "$@"
