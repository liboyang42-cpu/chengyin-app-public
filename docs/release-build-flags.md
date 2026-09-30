# Public build configuration

This client needs a compatible backend. The default API host is the reserved,
non-operational `api.example.invalid`; no production service is configured.

Set `API_BASE_URL` explicitly for your own backend:

```sh
flutter run --dart-define=API_BASE_URL=https://your-backend.example/api
flutter build ios --release --no-codesign --dart-define=API_BASE_URL=https://your-backend.example/api
```

`PACK_OPENING_ASSET` is optional. Without it, the existing static poster supports
the same three-tap progression and skip action. To use your own licensed Rive
animation, add its path to `pubspec.yaml` and set this define to the same path.
The animation must implement the existing MainScreen/ViewModel contract.

Apple Maps does not require an AMAP key. Android map parity is not supported.
Signing, bundle identifiers, WeChat application identifiers, associated domains,
support contacts and legal documents must be configured for your distribution.
An unsigned CI build is not a signed App Store release or device acceptance.
