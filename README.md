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

Work in progress. Nothing is published yet.

## License

The build scripts in this repository are MIT licensed. The published LLVM
binaries are under LLVM's own license (Apache-2.0 with LLVM exceptions).
