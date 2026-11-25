#!/bin/bash
# Check an install tree has what makes it worth using over Homebrew's.
#   scripts/verify-macos.sh <prefix>
set -euo pipefail

prefix=$(cd "${1:?usage: verify-macos.sh <prefix>}" && pwd)
lib="$prefix/lib"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"

# Optimized: llvm::LiveRange::find(SlotIndex) is 24 instructions optimized and
# 51 at -O0 (Homebrew's static libraries) on arm64.
ar x "$lib/libLLVMCodeGen.a" LiveInterval.cpp.o
file LiveInterval.cpp.o | grep -q "Mach-O" || { echo "FAIL: not Mach-O"; exit 1; }
n=$(xcrun llvm-objdump --no-show-raw-insn \
      --disassemble-symbols=__ZN4llvm9LiveRange4findENS_9SlotIndexE \
      LiveInterval.cpp.o | grep -cE '^[[:space:]]+[0-9a-f]+:')
echo "LiveRange::find: $n instructions"
[ "$n" -gt 0 ] && [ "$n" -le 35 ] || { echo "FAIL: expected 1..35 instructions"; exit 1; }

# RTTI: culebra links the typeinfo of these LLVM classes.
ar x "$lib/libLLVMCore.a" Value.cpp.o
nm Value.cpp.o | grep -q "__ZTIN4llvm10CallbackVHE" || { echo "FAIL: no RTTI"; exit 1; }

# Nothing outside the system.
for a in "$lib"/libLLVM*.a; do
  if nm -u "$a" 2>/dev/null | grep -qE '_(ZSTD|inflate|deflate|xml|el_)'; then
    echo "FAIL: $a refers to an external library"; exit 1
  fi
done

ls "$prefix/lib/cmake/llvm/LLVMConfig.cmake" >/dev/null
echo "verify OK"
