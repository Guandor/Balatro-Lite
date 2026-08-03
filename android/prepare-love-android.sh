#!/usr/bin/env bash
set -euo pipefail

# LÖVE Android 11.5. The immutable commit keeps release builds reproducible even
# if the upstream tag is moved or its main branch changes.
LOVE_ANDROID_COMMIT="7a32a370f9446581678dc2e7fbc4af3aac4643e6"

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 OUTPUT_DIRECTORY" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
output="$1"

if [ -e "$output" ]; then
  echo "Refusing to overwrite existing path: $output" >&2
  exit 1
fi

git init -q "$output"
git -C "$output" remote add origin https://github.com/love2d/love-android.git
git -C "$output" fetch -q --depth 1 origin "$LOVE_ANDROID_COMMIT"
git -C "$output" checkout -q --detach FETCH_HEAD
git -C "$output" submodule update --init --depth 1

cp -R "$repo_root/android/overlay/." "$output/"
cp "$repo_root/android/gradle.properties" "$output/gradle.properties"

mkdir -p "$output/app/src/main/assets/patches"
cp "$repo_root/balatro/patches/small_screen.lua" \
  "$output/app/src/main/assets/patches/small_screen.lua"
cp "$repo_root/balatro/patches/options.lua" \
  "$output/app/src/main/assets/patches/options.lua"
cp "$repo_root/balatro/patches/controls.lua" \
  "$output/app/src/main/assets/patches/controls.lua"
cp "$repo_root/balatro/patches/perf.lua" \
  "$output/app/src/main/assets/patches/perf.lua"
cp "$repo_root/balatro/resources/fonts/Nunito-Black.ttf" \
  "$output/app/src/main/assets/patches/Nunito-Black.ttf"

echo "Prepared LÖVE Android at $output"
