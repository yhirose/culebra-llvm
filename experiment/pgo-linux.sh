#!/bin/bash
# Experiment: what does PGO of LLVM buy culebra's --jit on Linux x86-64?
#   experiment/pgo-linux.sh <culebra checkout> <O2|O3>
# Leaves out/bin/{own,pgo}-<level> (and apt22 with O3) for experiment/measure.py.
# Variants: apt22 (what culebra's Linux builds link today), own (the pinned
# version built here), pgo (own + GCC PGO trained by culebra --jit).
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/llvm.env"
culebra=$(cd "${1:?usage: pgo-linux.sh <culebra checkout> <O2|O3>}" && pwd)
level=${2:?usage: pgo-linux.sh <culebra checkout> <O2|O3>}
jobs=$(nproc)
work="$root/src"
out="$root/out"
prof="$out/profile"
mkdir -p "$work" "$out" "$prof"
export CC=gcc-14 CXX=g++-14

tarball="$work/llvm-project-$LLVM_VERSION.src.tar.xz"
curl -fL --retry 3 -sS -o "$tarball" "$LLVM_SOURCE_URL"
echo "$LLVM_SOURCE_SHA256  $tarball" | sha256sum -c -
tar -xf "$tarball" -C "$work"
srcdir="$work/llvm-project-$LLVM_VERSION.src"

# Programs measured; training never sees them.
measured="test_core test_kauai test_runtime_errors test_value_inline test_typed_fields test_class"

# build_llvm <build dir> <prefix> [compile flags]
build_llvm() {
  local build=$1 prefix=$2 flags=${3:-} start
  start=$(date +%s)
  cmake -S "$srcdir/llvm" -B "$build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS_RELEASE="-$level -DNDEBUG" \
    -DCMAKE_CXX_FLAGS_RELEASE="-$level -DNDEBUG" \
    -DCMAKE_C_FLAGS="$flags" -DCMAKE_CXX_FLAGS="$flags" \
    -DCMAKE_EXE_LINKER_FLAGS="$flags" \
    -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DLLVM_TARGETS_TO_BUILD="X86;WebAssembly" \
    -DLLVM_ENABLE_RTTI=ON -DLLVM_ENABLE_ASSERTIONS=OFF \
    -DLLVM_BUILD_TOOLS=OFF -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_INCLUDE_DOCS=OFF -DLLVM_ENABLE_BINDINGS=OFF \
    -DLLVM_ENABLE_PLUGINS=OFF -DLLVM_ENABLE_ZSTD=OFF -DLLVM_ENABLE_ZLIB=OFF \
    -DLLVM_ENABLE_LIBXML2=OFF -DLLVM_ENABLE_LIBEDIT=OFF \
    -DLLVM_ENABLE_FFI=OFF -DLLVM_ENABLE_TERMINFO=OFF > /dev/null
  cmake --build "$build" -j "$jobs" > "$build.log" || { tail -50 "$build.log"; exit 1; }
  rm -rf "$prefix"
  cmake --install "$build" > /dev/null
  echo "llvm $(basename "$build"): $(( $(date +%s) - start )) s"
}

# build_culebra <name> <LLVMConfig dir> [linker flags]
build_culebra() {
  local name=$1 llvm=$2 ldflags=${3:-} start
  start=$(date +%s)
  cmake -S "$culebra" -B "$out/culebra-$name" \
    -DCMAKE_BUILD_TYPE=Release -DCULEBRA_ENABLE_JIT=ON -DCULEBRA_LTO=OFF \
    -DCULEBRA_DEV_NO_RT=ON -DLLVM_DIR="$llvm" \
    -DCMAKE_EXE_LINKER_FLAGS="$ldflags" > "$out/culebra-$name.log" 2>&1 ||
    { tail -50 "$out/culebra-$name.log"; exit 1; }
  cmake --build "$out/culebra-$name" --target culebra -j 3 >> "$out/culebra-$name.log" 2>&1 ||
    { tail -50 "$out/culebra-$name.log"; exit 1; }
  echo "culebra $name: $(( $(date +%s) - start )) s"
}

if [ "$level" = O3 ]; then
  build_culebra apt22 /usr/lib/llvm-22/lib/cmake/llvm
fi

build_llvm "$work/build-own" "$out/llvm-own"
build_culebra own "$out/llvm-own/lib/cmake/llvm"
rm -rf "$work/build-own"

# GCC finds a profile by object path, so both PGO phases use one build dir.
gen="-fprofile-generate=$prof"
build_llvm "$work/build-pgo" "$out/llvm-pgo" "$gen"
build_culebra train "$out/llvm-pgo/lib/cmake/llvm" "$gen"
rm -rf "$prof"; mkdir -p "$prof"   # drop what the build itself recorded
ran=0; failed=0; start=$(date +%s)
cd "$culebra"
for f in tests/*.cul; do
  case " $measured " in *" $(basename "$f" .cul) "*) continue ;; esac
  if timeout 300 "$out/culebra-train/culebra" --jit "$f" </dev/null >/dev/null 2>&1; then
    ran=$((ran + 1))
  else
    failed=$((failed + 1))
  fi
done
cd "$root"
echo "training: $ran ran, $failed failed, $(( $(date +%s) - start )) s, $(find "$prof" -name '*.gcda' | wc -l) gcda"
rm -rf "$out/culebra-train"

# -fprofile-partial-training: what training never reached stays optimized as
# usual instead of for size.
use="-fprofile-use=$prof -fprofile-partial-training -fprofile-correction -Wno-missing-profile -Wno-coverage-mismatch"
rm -rf "$work/build-pgo"
build_llvm "$work/build-pgo" "$out/llvm-pgo" "$use"
build_culebra pgo "$out/llvm-pgo/lib/cmake/llvm"

mkdir -p "$out/bin"
cp "$out/culebra-own/culebra" "$out/bin/own-$level"
cp "$out/culebra-pgo/culebra" "$out/bin/pgo-$level"
if [ "$level" = O3 ]; then cp "$out/culebra-apt22/culebra" "$out/bin/apt22"; fi
du -sh "$out"/llvm-own "$out"/llvm-pgo
