#!/bin/bash
# Build / test / run this package with the locally-compiled patched Swift
# toolchain that PropertyTestingKit requires (parameter packs + swift-testing
# @_spi). Mirrors PropertyTestingKit/scripts/build-local-toolchain.sh.
#
# Usage:
#   ./scripts/swift-toolchain.sh build [args...]
#   ./scripts/swift-toolchain.sh test  [args...]
#   ./scripts/swift-toolchain.sh run   <product> [args...]
#   ./scripts/swift-toolchain.sh env            # print the runtime env (for running built binaries)
#
# Override BUILD_ROOT if your toolchain build lives elsewhere.
set -e

BUILD_ROOT="${BUILD_ROOT:-/Users/fnord/Documents/OpenSourceDev/build/Ninja-RelWithDebInfoAssert}"
SWIFT_BUILD_DIR="$BUILD_ROOT/swift-macosx-arm64"
SWIFTPM_DIR="$BUILD_ROOT/swiftpm-macosx-arm64/arm64-apple-macosx/release"
SWIFTTESTING_DIR="$BUILD_ROOT/swifttesting-macosx-arm64"

LOCAL_SWIFTC="$SWIFT_BUILD_DIR/bin/swiftc"
LOCAL_RUNTIME="$SWIFT_BUILD_DIR/lib/swift/macosx"
TESTING_FLAGS="-Xswiftc -I$SWIFTTESTING_DIR/swift"

# The patched toolchain matches the Xcode-beta SDK; the CommandLineTools SDK is
# too old and fails to resolve C++ stdlib headers (e.g. <type_traits>) for PTK's
# CLLVMSymbolizer target.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"

# package-benchmark (transitive via PTK) wants jemalloc unless disabled.
export BENCHMARK_DISABLE_JEMALLOC="${BENCHMARK_DISABLE_JEMALLOC:-1}"

if [ ! -f "$LOCAL_SWIFTC" ]; then
    echo "error: local swiftc not found at $LOCAL_SWIFTC (set BUILD_ROOT)" >&2
    exit 1
fi

cd "$(dirname "$0")/.."

CMD="${1:-build}"; shift || true
case "$CMD" in
    build)
        DYLD_LIBRARY_PATH="$LOCAL_RUNTIME" SWIFT_EXEC="$LOCAL_SWIFTC" \
            "$SWIFTPM_DIR/swift-build" $TESTING_FLAGS "$@"
        ;;
    test)
        DYLD_LIBRARY_PATH="$LOCAL_RUNTIME" SWIFT_EXEC="$LOCAL_SWIFTC" \
            "$SWIFTPM_DIR/swift-test" $TESTING_FLAGS "$@"
        ;;
    run)
        DYLD_LIBRARY_PATH="$LOCAL_RUNTIME" SWIFT_EXEC="$LOCAL_SWIFTC" \
            "$SWIFTPM_DIR/swift-run" $TESTING_FLAGS "$@"
        ;;
    env)
        # Print the env needed to run an already-built binary directly.
        echo "DYLD_LIBRARY_PATH=$LOCAL_RUNTIME"
        ;;
    *)
        echo "usage: $0 {build|test|run|env} [args...]" >&2
        exit 2
        ;;
esac
