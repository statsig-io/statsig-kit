#!/usr/bin/env bash

set -euo pipefail

PLATFORM_RAW="${INPUT_PLATFORM:-ios}"
PLATFORM="$(echo "${PLATFORM_RAW}" | tr '[:upper:]' '[:lower:]')"

case "${PLATFORM}" in
  macos)
    echo "Platform is macOS; no simulator preparation needed."
    echo "destination=platform=macOS" >> "${GITHUB_OUTPUT}"
    exit 0
    ;;
  ios)
    PLATFORM_LABEL="iOS"
    RUNTIME_REGEX="^iOS "
    DEVICE_NAME="iPhone SE (3rd generation)"
    ;;
  tvos)
    PLATFORM_LABEL="tvOS"
    RUNTIME_REGEX="^tvOS "
    DEVICE_NAME="Apple TV"
    ;;
  visionos)
    PLATFORM_LABEL="visionOS"
    RUNTIME_REGEX="^visionOS "
    DEVICE_NAME="Apple Vision Pro"
    ;;
  *)
    echo "Unsupported platform input: ${PLATFORM_RAW}"
    echo "Expected one of: ios, tvos, visionos, macos"
    exit 1
    ;;
esac

# Pick the first available runtime identifier for the selected platform, e.g.:
# com.apple.CoreSimulator.SimRuntime.iOS-26-2
RUNTIME_ID="$(
  xcrun simctl list runtimes \
    | awk -v re="${RUNTIME_REGEX}" '$0 ~ re && $0 !~ /unavailable/ {print $NF; exit}'
)"
RUNTIME_LABEL="$(
  xcrun simctl list runtimes \
    | awk -v re="${RUNTIME_REGEX}" '$0 ~ re && $0 !~ /unavailable/ {print $1" "$2; exit}'
)"

if [ -z "${RUNTIME_ID}" ]; then
  echo "No available ${PLATFORM_LABEL} simulator runtime found."
  xcrun simctl list runtimes
  exit 1
fi

# Resolve the device type identifier dynamically from the device name.
DEVICE_TYPE="$(
  xcrun simctl list devicetypes \
    | awk -v name="${DEVICE_NAME}" 'index($0, name) {print $NF; exit}'
)"
if [ -z "${DEVICE_TYPE}" ]; then
  echo "No device type found for: ${DEVICE_NAME}"
  xcrun simctl list devicetypes
  exit 1
fi

SIM_NAME="Statsig-CI-${PLATFORM_LABEL}"

# Prefer an existing compatible simulator in the selected runtime, if available.
SIM_ID="$(
  xcrun simctl list devices \
    | awk -v runtime="${RUNTIME_LABEL}" -v name="${DEVICE_NAME}" '
        $0 ~ "^-- "runtime" --" { in_runtime=1; next }
        in_runtime && /^-- / { in_runtime=0 }
        in_runtime && index($0, name) { print; exit }
      ' \
    | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/'
)"

if [ -n "${SIM_ID}" ]; then
  echo "Using existing simulator ${DEVICE_NAME} (${SIM_ID}) in ${RUNTIME_LABEL}"
else
  # Fall back to creating a fresh simulator if none exists.
  SIM_ID="$(xcrun simctl create "${SIM_NAME}" "${DEVICE_TYPE}" "${RUNTIME_ID}")"
  echo "Created simulator ${SIM_NAME} (${SIM_ID}) using ${RUNTIME_ID}"
fi

# Boot only if needed; simctl boot fails if the device is already booted.
SIM_STATE="$(
  xcrun simctl list devices \
    | awk -v id="${SIM_ID}" 'index($0, id) { print; exit }' \
    | sed -E 's/.*\) \(([^)]+)\).*/\1/'
)"

if [ "${SIM_STATE}" != "Booted" ]; then
  xcrun simctl boot "${SIM_ID}"
else
  echo "Simulator ${SIM_ID} is already booted; skipping boot."
fi

DESTINATION="platform=${PLATFORM_LABEL} Simulator,id=${SIM_ID}"
echo "destination=${DESTINATION}" >> "${GITHUB_OUTPUT}"
