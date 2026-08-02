# Balatro Lite for Android

The Android release is a game-free LÖVE 11.5 wrapper. On first launch it asks
the player for `Balatro.exe` (or `Balatro.love`), verifies the supported game
layout, removes the fused Windows executable prefix, applies Balatro Lite's
handheld patch plus the required Android compatibility edits, and starts the
result with LÖVE.

After the game file is accepted, the first launch asks which screen layout to
use and whether to enable the performance changes. Those answers are stored in
the app's private preferences and determine how the imported archive is built.
To bring over a Steam save, put `meta.jkr`, `profile.jkr`, and `save.jkr` in a
ZIP and choose **Import Save (.zip)**. This replaces profile 1.

The game's Options menu includes **Initialize Port Settings**; selecting it
marks setup to run again when the app is next started.

The selected game and patched `.love` archive stay in the app's private storage.
They are never uploaded or added to the APK. Saves are written to the app's
external files directory at
`Android/data/io.github.guandor.balatrolite/files/save/balatro-lite/`. The first
release using that directory copies any saves from the former private location
without overwriting files already present there. Android 11 and newer may still
restrict which file managers can browse `Android/data`.

An app update rebuilds the patch from the private original automatically.
Clearing the app's storage or uninstalling it removes the imported game and may
also remove the app-specific external save directory, depending on the device.

## Supported game

The patch is deliberately pinned to the Steam `1.0.1o` archive. Each textual
edit has an expected match count; a different game version fails before a
partially patched game is installed.

## Local debug build

Install JDK 17, Android SDK API 34, Android Build Tools 34.0.0, and Android NDK
25.2.9519653. Then, from the repository root:

```bash
bash android/prepare-love-android.sh /tmp/balatro-lite-love-android
cd /tmp/balatro-lite-love-android
./gradlew assembleNormalNoRecordDebug
```

The preparation script checks out the immutable LÖVE Android 11.5 commit and
its pinned LÖVE submodule, overlays the importer, and copies only the Balatro
Lite Lua patch modules and the redistributable Nunito font into the APK assets.
It never reads or copies `Balatro.exe`.

## Release signing

Tagged releases build the PortMaster zip and Android APK together. Configure
these GitHub Actions secrets before pushing a release tag:

- `ANDROID_KEYSTORE_BASE64` — the release JKS file encoded as one base64 string
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Keep the keystore and passwords backed up. Every update must use the same key or
Android will reject it. The workflow aligns and signs the release APK, verifies
the signature, and rejects the artifact if it contains any `.exe` or `.love`
file.

One way to create a key is:

```bash
keytool -genkeypair -v -keystore balatro-lite-release.jks \
  -alias balatro-lite -keyalg RSA -keysize 4096 -validity 10000
base64 -w0 balatro-lite-release.jks
```

On PowerShell, encode the key with:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("balatro-lite-release.jks"))
```

Do not commit the keystore or its passwords.
