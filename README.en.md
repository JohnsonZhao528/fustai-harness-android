<p align="center">
  <a href="README.md">简体中文</a> · <b>English</b>
</p>

<p align="center">
  The Android client for <b>FustAI Harness</b>: sign in with your FustAI account and run the FustAI engine on the phone itself.
</p>

> This repository is a modified version of [dsh-Go](https://github.com/ccch1mneyyy/dsh-Go) (AGPL-3.0). Changes and their dates are listed in [MODIFICATIONS.md](MODIFICATIONS.md).

## What this is

FustAI Harness puts the FustAI engine in an Android phone: chat, local execution, plugins, skills, and scheduled tasks all run on the phone. The desktop app and the phone share one FustAI account, with no pairing code or computer binding.

Only Android is maintained here. `app/ios/` and `docs/guide/harmony/` are kept from upstream and are neither built nor verified on this branch.

## Differences from upstream

- Branding: DSH Go / Deepy → FustAI Harness; application id `com.fustai.harness`, plus app name, icons, splash, and the `fustai://` URL scheme.
- Account: the phone signs in with a FustAI account (in-app OAuth PKCE with a loopback callback); credentials stay on-device in `flutter_secure_storage`.
- Remote access: the scan-to-pair entry point is removed; SSH hosts and Remote account connections remain.
- Payments: top-up and balance entries are removed.
- Dependencies: `mobile_scanner` is removed, taking ML Kit barcode scanning and CameraX with it; on-device OCR remains.
- Guides: `docs/guide` and the in-app guide use FustAI wording.

## Build

Requires the Flutter SDK (Dart 3.9+), the Android SDK, and JDK 17.

```sh
cd app
flutter pub get
flutter build apk --release
```

## License and attribution

- Code is released under [AGPL-3.0](LICENSE); derivative works must stay open.
- Upstream: dsh-Go by ccch1mneyyy; this repository keeps its commit history.
- Third-party components and assets are credited in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
- The upstream DSH Go name, marks, and the Deepy mascots are not covered by AGPL; the app ships FustAI Harness assets instead. Upstream marketing images kept under `docs/` and `site/` are provenance only and must not be reused.