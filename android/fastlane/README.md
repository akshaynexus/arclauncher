# Fastlane — Arc Launcher (Android TV)

Automates Google Play uploads and Android TV screenshot capture.
Run lanes from the `android/` directory: `cd android && fastlane <lane>`.

## Setup

1. **Install fastlane** (one of):
   - Bundler: `bundle install` then `cd android && bundle exec fastlane <lane>`
   - Global: `gem install fastlane`

2. **Google Play service account** (never committed). Create a service account in
   Google Cloud + Play Console → *Setup → API access*, grant it release
   permissions, download the JSON, then provide it via ONE of:
   - File: place it at `android/fastlane/google_play_api_key.json` *(gitignored)*
   - `export SUPPLY_JSON_KEY=/abs/path/to/key.json`
   - `export GOOGLE_PLAY_API_KEY="$(cat key.json)"` *(raw JSON — used by CI)*

   Validate with: `fastlane run validate_play_store_json_key json_key:fastlane/google_play_api_key.json`

3. **App signing** (never committed). Gradle reads the keystore from
   `android/local.properties` (`storeFile/storePassword/keyAlias/keyPassword`)
   or from `SIGNING_KEYSTORE_PASSWORD` / `SIGNING_KEY_ALIAS` / `SIGNING_KEY_PASSWORD`
   env vars with the keystore at `android/app/upload-keystore.jks`.

> ⚠️ **First upload must be manual.** The Play API cannot create a brand-new app
> or do the *very first* upload of a new package. Upload one AAB and create the
> listing in the Play Console web UI once; after that, every lane below works.

## Lanes

| Lane | What it does |
|------|--------------|
| `build_aab` | `flutter build appbundle --release` → `build/app/outputs/bundle/release/app-release.aab` |
| `deploy` | Upload AAB to **internal**, binary only (used by CI) |
| `promote` | Promote latest internal build → **production** (used by CI) |
| `internal` | `build_aab` + upload to internal **with** metadata + TV screenshots |
| `beta` | Same, to the closed **beta** track |
| `production` | Same, to **production** |
| `metadata` | Upload store text + TV screenshots only (no binary) |
| `validate` | Build + dry-run the upload (`validate_only`), commits nothing |
| `screenshots` | Capture fresh TV screenshots (`fastlane screenshots sync:true` also copies them into metadata) |

Examples:
```bash
cd android
fastlane internal              # build + ship to internal testers w/ store assets
fastlane production            # build + ship to production
fastlane screenshots sync:true # regenerate TV screenshots and update metadata
fastlane validate              # safe dry run
```

## Store metadata

Canonical metadata lives at the **repo root** under
`fastlane/metadata/android/en-US/` (title, short/full description,
`changelogs/<versionCode>.txt`, `images/tvScreenshots/`, `images/tvBanner.png`).
The lanes point `metadata_path` there. The changelog file must be named after the
`versionCode` (the `+NNNN` in `pubspec.yaml` `version:`), e.g. `4106.txt`, or
fall back to `default.txt`.

## Screenshots

See `../../tool/tv_screenshots.sh`. It creates/boots a `tv_1080p` Android TV AVD
(1920×1080, 16:9), runs the Flutter `integration_test` driver
(`integration_test/screenshot_test.dart` + `test_driver/integration_test.dart`),
and writes PNGs to `./screenshots/`. `--sync-metadata` copies them into
`fastlane/metadata/android/en-US/images/tvScreenshots/`.

> fastlane **screengrab** is not used: it relies on Android Espresso/instrumentation,
> which Flutter apps do not produce. Flutter's `integration_test` is the supported path.
