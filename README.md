# culebra-llvm

Prebuilt static LLVM libraries for building [culebra](https://github.com/yhirose/culebra).

## Why

culebra links LLVM statically (its JIT and AOT backends). The static libraries
that package managers ship are not always built the way culebra needs:

- Homebrew's `llvm` bottle converts its ThinLTO bitcode archives to Mach-O
  without an optimization flag, so every static library is compiled at `-O0`
  (for example `llvm::LiveRange::find` is 51 instructions, against 24 in the
  optimized build). LLVM's own code generation inside culebra runs about twice
  as slow as it would with optimized libraries.
- LLVM's official macOS release archives hold ThinLTO bitcode, which Apple's
  linker cannot read, and are built without RTTI.

This repository builds only what culebra links (`core support orcjit native
passes bitreader bitwriter` and the WebAssembly backend), with RTTI on and
assertions off, and publishes the result as release assets.

## Status

Published: release
[`llvm-23.1.5-r1`](https://github.com/yhirose/culebra-llvm/releases/tag/llvm-23.1.5-r1),
for macOS arm64 only (Apple Silicon, built for apple-m1 and later; there is no
Intel Mac build).

- LLVM 23.1.5, targets AArch64 and WebAssembly, RTTI on, assertions off, no
  external libraries.
- About 45 MB as `.tar.zst`, 221 MB unpacked.
- Built by this repository's CI on `macos-15` in about 30 minutes, from the
  tag's commit.

Linux and Windows: not published yet.

### Making a release

Push a tag named `llvm-<LLVM version>-r<revision>`. The workflow builds,
verifies, and attaches the archive and its `.sha256` to the release. The
verification checks that `LiveRange::find` is at most 35 instructions (the
libraries are optimized) and that the `CallbackVH` typeinfo exists (RTTI is on).

### How culebra uses it

culebra's `misc/prebuilt_llvm.env` pins a release tag, asset name and SHA256
per platform, and its `justfile` passes the unpacked directory as `-DLLVM_DIR`.

One measured effect: for a large program, culebra's `--jit` translation took
about 98 s with Homebrew's llvm static libraries (compiled at `-O0`) and about
61 s with these (3 runs each, same machine, load not controlled).

## License

The build scripts in this repository are MIT licensed. The published LLVM
binaries are under LLVM's own license (Apache-2.0 with LLVM exceptions).
