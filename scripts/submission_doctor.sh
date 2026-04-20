#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_ID="com.skinlit.SkinLit"
BASE_URL="https://skinlit.lat"
SKIP_TESTS=0
SKIP_REMOTE_SITE=0
SKIP_ASC=0

usage() {
  cat <<'EOF'
Usage: ./scripts/submission_doctor.sh [options]

Options:
  --skip-tests         Skip simulator test execution
  --skip-remote-site   Skip public docs-site checks
  --skip-asc           Skip App Store Connect API checks
  --base-url URL       Override docs-site base URL
  --bundle-id ID       Override bundle identifier
  -h, --help           Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-tests)
      SKIP_TESTS=1
      shift
      ;;
    --skip-remote-site)
      SKIP_REMOTE_SITE=1
      shift
      ;;
    --skip-asc)
      SKIP_ASC=1
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

step() {
  printf '\n==> %s\n' "$1"
}

warn() {
  printf 'warning: %s\n' "$1" >&2
}

step "Release verification"
release_args=()
if [[ "$SKIP_TESTS" -eq 1 ]]; then
  release_args+=(--skip-tests)
fi

set +e
"$ROOT_DIR/scripts/release_verification.sh" "${release_args[@]}"
release_status=$?
set -e

case "$release_status" in
  0)
    ;;
  2)
    warn "Simulator infrastructure failed during tests. Build passed, but you still need an equivalent device/TestFlight smoke pass."
    ;;
  *)
    exit "$release_status"
    ;;
esac

step "Docs site validation"
docs_args=(--base-url "$BASE_URL" --bundle-id "$BUNDLE_ID")
if [[ "$SKIP_REMOTE_SITE" -eq 1 ]]; then
  docs_args+=(--skip-remote)
fi
"$ROOT_DIR/scripts/validate_docs_site.sh" "${docs_args[@]}"

if [[ "$SKIP_ASC" -eq 1 ]]; then
  warn "Skipping App Store Connect API checks by request."
elif [[ -f "$ROOT_DIR/Config/Environment/app_store_connect.env" ]]; then
  step "App Store Connect doctor"
  ruby "$ROOT_DIR/scripts/app_store_connect_cli.rb" doctor --bundle-id "$BUNDLE_ID"
else
  warn "Config/Environment/app_store_connect.env is missing, so App Store Connect doctor was skipped."
fi

step "Submission checklist reminder"
cat <<'EOF'
- Verify guest bootstrap, first scan, Sign in with Apple, Sign in with Google, purchase/restore, and delete-account flows on a real device or TestFlight.
- Confirm App Privacy answers in App Store Connect match the current cloud selfie upload and local processed-preview behavior.
- Confirm Agreements, Tax, and Banking are active before submission.
EOF
