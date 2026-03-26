#!/bin/sh
set -eu

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  echo "usage: $0 <version-tag> [release-notes-file]" >&2
  exit 1
fi

VERSION="$1"
NOTES_FILE="${2:-}"
ROOT_DIR="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/MacinHoff.xcodeproj"
DERIVED_DATA_PATH="$ROOT_DIR/Build/DerivedData"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/MacinHoff.app"
RELEASE_DIR="$ROOT_DIR/Build/Releases/$VERSION"
ZIP_PATH="$RELEASE_DIR/MacinHoff-$VERSION.zip"

cd "$ROOT_DIR"

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "working tree must be clean before creating a release" >&2
  exit 1
fi

if git rev-parse "$VERSION" >/dev/null 2>&1; then
  echo "tag $VERSION already exists" >&2
  exit 1
fi

xcodegen generate
xcodebuild -project "$PROJECT_PATH" -scheme MacinHoff -configuration Debug -derivedDataPath "$DERIVED_DATA_PATH" build

mkdir -p "$RELEASE_DIR"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

git tag -a "$VERSION" -m "Release $VERSION"
git push origin main
git push origin "$VERSION"

PRERELEASE_FLAG=""
case "$VERSION" in
  *alpha*|*beta*|*rc*)
    PRERELEASE_FLAG="--prerelease"
    ;;
esac

if [ -n "$NOTES_FILE" ]; then
  gh release create "$VERSION" "$ZIP_PATH" --title "$VERSION" $PRERELEASE_FLAG --notes-file "$NOTES_FILE"
else
  gh release create "$VERSION" "$ZIP_PATH" --title "$VERSION" $PRERELEASE_FLAG --generate-notes
fi

echo "release created: $VERSION"
