#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_SCRIPT="$ROOT_DIR/scripts/package_docs_site.sh"
OUTPUT_ZIP="$ROOT_DIR/skinlit-pages.zip"
BASE_URL="https://skinlit.lat"
SKIP_PACKAGE=0
SKIP_REMOTE=0
BUNDLE_ID="com.skinlit.SkinLit"

usage() {
  cat <<'EOF'
Usage: ./scripts/validate_docs_site.sh [options]

Options:
  --skip-package        Skip rebuilding skinlit-pages.zip
  --skip-remote         Skip public URL checks
  --base-url URL        Validate a non-production deployment
  --bundle-id ID        Expected bundle id suffix in the AASA file
  -h, --help            Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-package)
      SKIP_PACKAGE=1
      shift
      ;;
    --skip-remote)
      SKIP_REMOTE=1
      shift
      ;;
    --base-url)
      BASE_URL="${2:-}"
      shift 2
      ;;
    --bundle-id)
      BUNDLE_ID="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

check_zip_contains() {
  local pattern="$1"
  grep -Fq "$pattern" <<<"$ZIP_LISTING"
}

validate_aasa_payload() {
  local source="$1"

  ruby -rjson -e '
    bundle_id = ARGV.fetch(0)
    payload = JSON.parse(STDIN.read)
    details = Array(payload.dig("applinks", "details"))
    abort("AASA is missing applinks.details") if details.empty?
    unless details.any? { |item| item.fetch("appID", "").end_with?(".#{bundle_id}") }
      abort("AASA is missing an appID that ends with .#{bundle_id}")
    end
    unless details.any? { |item| Array(item["paths"]).any? { |path| ["/r/*", "/referral", "/referral/", "/referral/*"].include?(path) } }
      abort("AASA is missing referral paths")
    end
  ' "$BUNDLE_ID" <"$source"
}

check_remote_url() {
  local label="$1"
  local url="$2"
  local status
  status="$(curl -sS -o /dev/null -w '%{http_code}' "$url")"
  case "$status" in
    200|301|302|307|308)
      echo "Remote check passed: $label ($status)"
      ;;
    *)
      echo "Remote check failed: $label returned HTTP $status" >&2
      return 1
      ;;
  esac
}

if [[ "$SKIP_PACKAGE" -ne 1 ]]; then
  "$PACKAGE_SCRIPT" "$OUTPUT_ZIP"
fi

if [[ ! -f "$OUTPUT_ZIP" ]]; then
  echo "Expected packaged site archive at $OUTPUT_ZIP" >&2
  exit 1
fi

ZIP_LISTING="$(zipinfo -1 "$OUTPUT_ZIP")"

for required_path in \
  ".well-known/apple-app-site-association" \
  "_headers" \
  "privacy/index.html" \
  "terms/index.html" \
  "support/index.html" \
  "referral/index.html" \
  "404.html"
do
  if ! check_zip_contains "$required_path"; then
    echo "Packaged archive is missing $required_path" >&2
    exit 1
  fi
done

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

unzip -qq "$OUTPUT_ZIP" ".well-known/apple-app-site-association" -d "$TMP_DIR"
validate_aasa_payload "$TMP_DIR/.well-known/apple-app-site-association"
echo "Local archive validation passed."

if [[ "$SKIP_REMOTE" -eq 1 ]]; then
  exit 0
fi

check_remote_url "privacy" "$BASE_URL/privacy"
check_remote_url "terms" "$BASE_URL/terms"
check_remote_url "support" "$BASE_URL/support"
check_remote_url "referral" "$BASE_URL/referral/?code=ABC123"
check_remote_url "AASA" "$BASE_URL/.well-known/apple-app-site-association"

REMOTE_AASA="$TMP_DIR/remote-apple-app-site-association"
curl -fsSL "$BASE_URL/.well-known/apple-app-site-association" >"$REMOTE_AASA"
validate_aasa_payload "$REMOTE_AASA"

remote_content_type="$(
  curl -fsSI "$BASE_URL/.well-known/apple-app-site-association" \
    | awk -F': ' 'tolower($1) == "content-type" { print tolower($2) }' \
    | tr -d "\r" \
    | tail -n 1
)"

if [[ "$remote_content_type" != application/json* ]]; then
  echo "Unexpected AASA Content-Type: ${remote_content_type:-missing}" >&2
  exit 1
fi

echo "Remote docs site validation passed for $BASE_URL."
