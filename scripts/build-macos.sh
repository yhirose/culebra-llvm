#!/bin/bash
# Build the static LLVM libraries culebra links, for macOS arm64.
#   scripts/build-macos.sh [jobs]
# Output: out/prefix (an LLVM install tree) and out/llvm-<version>-macos-arm64.tar.zst
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/llvm.env"
jobs=${1:-$(sysctl -n hw.ncpu)}

work="$root/src"
out="$root/out"
prefix="$out/prefix"
mkdir -p "$work" "$out"

tarball="$work/llvm-project-$LLVM_VERSION.src.tar.xz"
if [ ! -f "$tarball" ]; then
  curl -fL --retry 3 -o "$tarball" "$LLVM_SOURCE_URL"
fi
echo "$LLVM_SOURCE_SHA256  $tarball" | shasum -a 256 -c -

srcdir="$work/llvm-project-$LLVM_VERSION.src"
[ -d "$srcdir" ] || tar -xf "$tarball" -C "$work"

# Only what culebra links: the native backend and WebAssembly (jit.h registers
# it for `culebra build --target=wasm32-...`). RTTI is on because culebra
# derives from LLVM classes (CallbackVH, raw_ostream, ObjectCache, ...); the
# official release archives are built without it. No external libraries, so
# the archives depend on nothing but the system.
build="$work/build"
cmake -S "$srcdir/llvm" -B "$build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_C_FLAGS=-mcpu=apple-m1 \
  -DCMAKE_CXX_FLAGS=-mcpu=apple-m1 \
  -DCMAKE_INSTALL_PREFIX="$prefix" \
  -DLLVM_TARGETS_TO_BUILD="AArch64;WebAssembly" \
  -DLLVM_ENABLE_RTTI=ON \
  -DLLVM_ENABLE_ASSERTIONS=OFF \
  -DLLVM_BUILD_TOOLS=OFF \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_BENCHMARKS=OFF \
  -DLLVM_INCLUDE_EXAMPLES=OFF \
  -DLLVM_INCLUDE_DOCS=OFF \
  -DLLVM_ENABLE_BINDINGS=OFF \
  -DLLVM_ENABLE_PLUGINS=OFF \
  -DLLVM_ENABLE_ZSTD=OFF \
  -DLLVM_ENABLE_ZLIB=OFF \
  -DLLVM_ENABLE_LIBXML2=OFF \
  -DLLVM_ENABLE_LIBEDIT=OFF \
  -DLLVM_ENABLE_FFI=OFF \
  -DLLVM_ENABLE_TERMINFO=OFF

grep -E "^CMAKE_(C|CXX)_FLAGS(_RELEASE)?:" "$build/CMakeCache.txt"
start=$(date +%s)
cmake --build "$build" -j "$jobs"
echo "build seconds: $(( $(date +%s) - start ))"

rm -rf "$prefix"
cmake --install "$build"

# What the archive was built with, so a consumer can tell whether it matches
# its own toolchain.
{
  echo "llvm: $LLVM_VERSION"
  echo "macos: $(sw_vers -productVersion)"
  echo "xcode: $(xcodebuild -version | tr '\n' ' ')"
  echo "clang: $(clang --version | head -1)"
  echo "targets: AArch64;WebAssembly"
  echo "rtti: ON"
} > "$prefix/BUILD_INFO.txt"

name="llvm-$LLVM_VERSION-macos-arm64"
tar -C "$prefix" -cf - . | zstd -19 -T0 -o "$out/$name.tar.zst" -f
shasum -a 256 "$out/$name.tar.zst" | tee "$out/$name.tar.zst.sha256"
du -sh "$prefix" "$out/$name.tar.zst"
