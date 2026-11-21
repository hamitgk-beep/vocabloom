#!/usr/bin/env bash
# Prepares the optional Zemberek-NLP (Apache-2.0, Java) Turkish analyzer for the lexicon tool:
#   1. checks that Java 21+ (java and javac) is installed,
#   2. downloads the jars listed in zemberek/jars.lock into build/lexicon/zemberek/lib and verifies each SHA-256,
#   3. compiles zemberek/ZemberekBridge.java into build/lexicon/zemberek/classes,
#   4. runs a smoke test ("evlerimizde" -> "ev").
# Nothing is installed system-wide, nothing is committed, the Flutter app is not touched. Re-running is safe.
#   bash tools/lexicon/setup_zemberek.sh
#   python3 tools/lexicon/run.py extract --source ... --text kitap.txt --engine zemberek
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
dest="${ZEMBEREK_HOME:-$root/build/lexicon/zemberek}"
lib="$dest/lib"
mkdir -p "$lib" "$dest/classes"

for tool in java javac; do
  command -v "$tool" >/dev/null || { echo "$tool not found: install a JDK 21 or newer (e.g. apt install openjdk-21-jdk-headless)" >&2; exit 1; }
done
major="$(java -XshowSettings:properties -version 2>&1 | sed -n 's/^ *java.specification.version = //p')"
if [ "${major%%.*}" -lt 21 ]; then
  echo "Java $major found; Zemberek 0.18.0 needs Java 21 or newer" >&2
  exit 1
fi

grep -v '^#' "$here/zemberek/jars.lock" | while IFS=$'\t' read -r file sha licence url; do
  [ -n "$file" ] || continue
  target="$lib/$file"
  if [ ! -f "$target" ] || ! echo "$sha  $target" | sha256sum -c --quiet - 2>/dev/null; then
    tmp="$target.part"
    curl -sSfL --retry 4 --retry-delay 2 -o "$tmp" "$url"
    if ! echo "$sha  $tmp" | sha256sum -c --quiet -; then
      rm -f "$tmp"
      echo "checksum mismatch for $file: refusing to use it" >&2
      exit 1
    fi
    mv "$tmp" "$target"
  fi
  echo "ok $file ($licence)"
done

cp="$(ls "$lib"/*.jar | tr '\n' ':')"
javac -nowarn -cp "$cp" -d "$dest/classes" "$here/zemberek/ZemberekBridge.java" 2>&1 | grep -v '^Picked up' || true
[ -f "$dest/classes/ZemberekBridge.class" ] || { echo "compilation failed" >&2; exit 1; }

out="$(printf 'Evlerimizde kitap okuduk.\n' | java -cp "$dest/classes:$cp" ZemberekBridge 2>/dev/null)"
echo "$out" | grep -q $'^Evlerimizde\tev\t' || { echo "smoke test failed:"$'\n'"$out" >&2; exit 1; }
echo "Zemberek ready in $dest"
