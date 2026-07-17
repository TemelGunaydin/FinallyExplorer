# FFF binary dependency

This directory vendors the FFF C API as a universal dynamic XCFramework for FinallyExplorer.

## Pinned upstream revision

- Repository: `dmtrKovalenko/fff`
- Release: `0.9.7-nightly.42f38ff`
- Commit: `42f38ff66e6c62475678f05ee60c3a311e341884`
- C options ABI: `FFF_CREATE_OPTIONS_VERSION 2`
- License: MIT; the unmodified upstream license is in `LICENSE`.

The matching release assets were downloaded with GitHub CLI. Their published and locally verified SHA-256 values are:

- `c-lib-aarch64-apple-darwin.dylib`: `7428eca3088a91d02b0737d6fd33082584dde55531e04deec6de8df90b6d0b7e`
- `c-lib-x86_64-apple-darwin.dylib`: `8aab817281862737ebf363840450c6d99b9a0fba9690a47a3a5d2acde08e8511`

The two thin libraries were combined with `lipo`. Their upstream absolute install name was replaced with `@rpath/libFFF.dylib`, and the resulting universal library was ad-hoc signed with identifier `com.finallyexplorer.fff`. The application archive must still embed and sign the dylib with the application signing identity.

## Artifact properties

- Platforms: macOS arm64 and x86_64
- Minimum macOS version: 13.0
- Swift/Clang module: `CFFF`
- Import: `import CFFF`
- Dynamic library: `FFF.xcframework/macos-arm64_x86_64/libFFF.dylib`
- Install name: `@rpath/libFFF.dylib`

`SHA256SUMS` records the final vendored files after repackaging.
