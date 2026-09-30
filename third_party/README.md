# Vendored native UI dependencies

These packages are checked in so Chengyin can keep narrowly reviewed iOS
patches reproducible instead of modifying the global Pub cache at build time.

## `native_liquid_glass`

- Upstream: <https://github.com/tienanh306201z/native_liquid_glass>
- Base revision: `fded1ae14dfc1d8802a9e4906f7b536c4e794780`
- License: BSD 3-Clause (see the package `LICENSE`)
- Local patches:
  - preserve VoiceOver names on icon-only `UITab`/`UISearchTab` items;
  - complete Dart alert futures after interactive dismissal;
  - use the package's UIKit `UIProgressView` on every supported iOS version.

## `image_cropper`

- Upstream: <https://github.com/hnvn/flutter_image_cropper>
- Base release: `11.0.0` (Pub checksum
  `46c8f9aae51c8350b2a2982462f85a129e77b04675d35b09db5499437d7a996b`)
- License: MIT (see the package `LICENSE`)
- Local patch: do not force fixed aspect ratios to swap dimensions after the
  caller explicitly locks portrait or landscape orientation.

`test/vendor_native_plugin_contract_test.dart` locks these patches. An upstream
upgrade must reapply or retire each patch deliberately and rerun the iOS build.
