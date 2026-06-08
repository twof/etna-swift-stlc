#!/bin/bash
# Run the built `stlc` solve binary with the patched toolchain's runtime on the
# dylib path. ETNA's `solve` capability invokes this.
#   run-stlc.sh <strategy> <property> [duration_seconds]
# The mutant under test is whichever marauder variant is active in the current
# build (ETNA activates it via source-swap + rebuild before calling this).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="${BUILD_ROOT:-/Users/fnord/Documents/OpenSourceDev/build/Ninja-RelWithDebInfoAssert}"
RT="$BUILD_ROOT/swift-macosx-arm64/lib/swift/macosx"
CONFIG="${CONFIG:-debug}"
exec env DYLD_LIBRARY_PATH="$RT" "$ROOT/.build/$CONFIG/stlc" "$@"
