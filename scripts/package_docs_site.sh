#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCS_DIR="$ROOT_DIR/docs"
OUTPUT_ZIP="${1:-$ROOT_DIR/skinlit-pages.zip}"
if [[ "$OUTPUT_ZIP" != /* ]]; then
  OUTPUT_ZIP="$ROOT_DIR/$OUTPUT_ZIP"
fi

if [[ ! -d "$DOCS_DIR" ]]; then
  echo "Docs directory not found at $DOCS_DIR" >&2
  exit 1
fi

if [[ ! -f "$DOCS_DIR/.well-known/apple-app-site-association" ]]; then
  echo "Missing docs/.well-known/apple-app-site-association" >&2
  exit 1
fi

if [[ ! -f "$DOCS_DIR/_headers" ]]; then
  echo "Missing docs/_headers" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

rsync -a --delete \
  --exclude '.DS_Store' \
  --exclude 'README.md' \
  --exclude 'Archive.zip' \
  "$DOCS_DIR"/ "$TMP_DIR"/
rm -f "$OUTPUT_ZIP"

(
  cd "$TMP_DIR"
  shopt -s dotglob nullglob
  entries=(*)
  zip -r -q "$OUTPUT_ZIP" "${entries[@]}" -x '*.DS_Store' '__MACOSX/*'
)

zip_listing="$(unzip -l "$OUTPUT_ZIP")"

if ! grep -Fq '.well-known/apple-app-site-association' <<<"$zip_listing"; then
  echo "Packaged archive is missing .well-known/apple-app-site-association" >&2
  exit 1
fi

if ! grep -Fq '_headers' <<<"$zip_listing"; then
  echo "Packaged archive is missing _headers" >&2
  exit 1
fi

echo "Created $OUTPUT_ZIP"
echo "Upload this ZIP to Cloudflare Pages using Direct Upload to preserve hidden files."
