Chengyin App — standalone Flutter client source candidate

Requires Flutter 3.44.2 / Dart 3.12.2. Run flutter pub get,
dart analyze lib test, then python3 tool/test_public.py.
Use flutter run --dart-define=API_BASE_URL=https://your-backend.example
with your own backend. The default api.example.invalid is intentionally
non-operational. See docs/release-build-flags.md for platform configuration.
The support number 18000000000 is a placeholder, not a contact.

No backend, original Git history, internal reports, production credentials,
signing certificates or original Actions logs are included. The unlicensed
cardpackopening3.riv asset is omitted; the existing poster and tap/skip flow
remain. Optional replacement artwork must be separately licensed.

Public CI uses GitHub standard macOS runners with Flutter 3.44.2; no self-hosted
runner or production secret is used. Jobs skip private repositories to avoid
paid preparation runs. Golden tests and needs-local-env tagged tests are
excluded explicitly; this is not full visual, device or production acceptance.
No signing, automatic deployment, TestFlight or App Store upload is configured.
The source has not yet passed a cloud run in its future standalone repository.

No new blanket MIT grant is made for original project code. Preserve upstream
licenses in third_party/image_cropper/LICENSE and
third_party/native_liquid_glass/LICENSE and dependency license obligations.
Remaining artwork ownership and redistribution rights need owner verification.
