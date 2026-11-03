#!/usr/bin/env bash
# Release build for one client: scripts/build.sh <client> <dev|prod> [apk|appbundle|ipa] [extra flutter args]
# Backend settings come from config/<env>.json. The output is copied to dist/SlotBook-<client>-<version>[-dev].<apk|aab|ipa>.
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
  echo "Usage: scripts/build.sh <client> <dev|prod> [apk|appbundle|ipa] [extra flutter args]"
  echo "Clients:"
  for f in lib/app/config/clients/*.dart; do
    name=$(basename "$f" .dart)
    [ "$name" != "client_config" ] && echo "  $name"
  done
  exit 1
}

CLIENT=${1:-}
ENV=${2:-}
TARGET=${3:-apk}
[ -z "$CLIENT" ] && usage
[ -f "lib/app/config/clients/$CLIENT.dart" ] || { echo "Unknown client \"$CLIENT\"."; usage; }
case "$ENV" in dev | prod) ;; *) echo "Unknown environment \"$ENV\". Use dev or prod."; usage ;; esac
[ -f "config/$ENV.json" ] || { echo "Missing config/$ENV.json: copy config/example.json and fill in the project's URL and anon key."; exit 1; }
case "$TARGET" in apk | appbundle | ipa) ;; *) echo "Unknown target \"$TARGET\"."; usage ;; esac
shift $(($# < 3 ? $# : 3))
SUFFIX=$([ "$ENV" = dev ] && echo -dev || true)

VERSION=$(grep -m1 '^version:' pubspec.yaml | awk '{print $2}')
echo "Building $CLIENT $TARGET v$VERSION against $ENV ..."
flutter build "$TARGET" --release --flavor "$CLIENT" "--dart-define-from-file=config/$ENV.json" "$@"

mkdir -p dist
case "$TARGET" in
  apk) SRC="build/app/outputs/flutter-apk/app-$CLIENT-release.apk"; EXT=apk ;;
  appbundle) SRC="build/app/outputs/bundle/${CLIENT}Release/app-$CLIENT-release.aab"; EXT=aab ;;
  ipa) SRC=$(ls build/ios/ipa/*.ipa | head -1); EXT=ipa ;;
esac
OUT="dist/SlotBook-$CLIENT-$VERSION$SUFFIX.$EXT"
cp "$SRC" "$OUT"
echo "Done: $OUT"
