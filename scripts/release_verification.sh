#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/SkinScore.xcodeproj"
SCHEME="SkinScore"
CONFIGURATION="Release"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/SkinScoreSubmissionDerivedData}"
LOG_DIR="${LOG_DIR:-$ROOT_DIR/.build/logs}"
RUN_TESTS=1
DESTINATION=""

usage() {
  cat <<'EOF'
Usage: ./scripts/release_verification.sh [options]

Options:
  --skip-tests              Build Release only
  --destination VALUE       Explicit xcodebuild destination string
  --derived-data-path PATH  Override DerivedData path
  -h, --help                Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-tests)
      RUN_TESTS=0
      shift
      ;;
    --destination)
      DESTINATION="${2:-}"
      shift 2
      ;;
    --derived-data-path)
      DERIVED_DATA_PATH="${2:-}"
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

mkdir -p "$LOG_DIR"

BUILD_LOG="$LOG_DIR/release-build.log"
TEST_LOG="$LOG_DIR/release-test.log"

pick_first_available_iphone_destination() {
  local line os_line os_version device_name udid
  line="$(
    xcrun simctl list devices available | awk '
      /^-- iOS / { os = $0; next }
      /iPhone/ && /\((Booted|Shutdown)\)/ {
        print os "|" $0
        exit
      }
    '
  )"

  if [[ -z "$line" ]]; then
    return 1
  fi

  os_line="${line%%|*}"
  line="${line#*|}"
  os_version="${os_line#-- iOS }"
  os_version="${os_version% --}"
  device_name="${line%% (*}"
  device_name="$(sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' <<<"$device_name")"
  udid="$(sed -E 's/.*\(([A-F0-9-]+)\).*/\1/' <<<"$line")"

  echo "platform=iOS Simulator,name=$device_name,OS=$os_version|$udid"
}

simulator_failure_detected() {
  local log_path="$1"
  rg -n -i \
    'mach error -308|CoreSimulator|simulator.*failed|failed to boot|unable to boot|timed out waiting for simulator|failed to launch|simctl' \
    "$log_path" >/dev/null 2>&1
}

echo "==> Building $SCHEME ($CONFIGURATION)"
xcodebuild \
  build \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  | tee "$BUILD_LOG"

echo "Release build succeeded."

if [[ "$RUN_TESTS" -ne 1 ]]; then
  echo "Skipping simulator tests."
  exit 0
fi

if [[ -z "$DESTINATION" ]]; then
  pick_output="$(pick_first_available_iphone_destination)" || {
    echo "No available iPhone simulator found for Release test verification." >&2
    exit 1
  }
  DESTINATION="${pick_output%%|*}"
  SIMULATOR_UDID="${pick_output##*|}"
else
  SIMULATOR_UDID=""
fi

if [[ -n "$SIMULATOR_UDID" ]]; then
  xcrun simctl boot "$SIMULATOR_UDID" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$SIMULATOR_UDID" -b
fi

echo "==> Running tests on $DESTINATION"
set +e
xcodebuild \
  test \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  | tee "$TEST_LOG"
status=${PIPESTATUS[0]}
set -e

if [[ "$status" -eq 0 ]]; then
  echo "Release simulator tests succeeded."
  exit 0
fi

if simulator_failure_detected "$TEST_LOG"; then
  echo "Simulator infrastructure failed during test verification. See $TEST_LOG" >&2
  exit 2
fi

echo "Release simulator tests failed. See $TEST_LOG" >&2
exit 1
