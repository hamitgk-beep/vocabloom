#!/usr/bin/env bash
# Turns the five build artifacts of one build.yml run into the ten files the
# 'latest' release carries. Used by the dry run in build.yml (every pull
# request and push) and by release.yml (the real release), so what a pull
# request checks is exactly what a release publishes.
#
#   tools/release/package.sh DIST
#
# DIST holds the downloaded artifacts as folders: Storilex-Windows,
# Storilex-Android (app-release.apk), Storilex-iOS (Storilex-unsigned.ipa),
# Storilex-macOS (Storilex.app's contents) and Storilex-Linux. The files are
# written next to them in DIST. Nothing is uploaded here.
set -euo pipefail
cd "$1"
for d in Storilex-Windows Storilex-Android Storilex-iOS Storilex-macOS Storilex-Linux; do
  [ -d "$d" ] || { echo "::error::Build artifact $d is missing"; exit 1; }
done
rm -rf legacy-windows
(cd Storilex-Windows && zip -qr ../Storilex-Windows.zip .)
cp Storilex-Android/app-release.apk Storilex-Android.apk
cp Storilex-iOS/Storilex-unsigned.ipa Storilex-iOS-unsigned.ipa
(cd Storilex-macOS && zip -qry ../Storilex-macOS.zip .)
tar -czf Storilex-Linux.tar.gz -C Storilex-Linux .
# Apps from before the rename look for the VocaBloom files, and on
# Windows they restart VocaBloom.exe after the update: their zip
# carries a copy under that name. The new app then moves the user's
# shortcuts to Storilex.exe, and the next update removes the copy.
cp -r Storilex-Windows legacy-windows
cp legacy-windows/Storilex.exe legacy-windows/VocaBloom.exe
(cd legacy-windows && zip -qr ../VocaBloom-Windows.zip .)
cp Storilex-Android.apk VocaBloom-Android.apk
cp Storilex-iOS-unsigned.ipa VocaBloom-iOS-unsigned.ipa
cp Storilex-macOS.zip VocaBloom-macOS.zip
cp Storilex-Linux.tar.gz VocaBloom-Linux.tar.gz
