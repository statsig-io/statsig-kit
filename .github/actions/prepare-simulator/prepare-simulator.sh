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
    RUNTIME_PREFIX="iOS"
    DEVICE_REGEX="^iPhone"
    ;;
  tvos)
    PLATFORM_LABEL="tvOS"
    RUNTIME_PREFIX="tvOS"
    DEVICE_REGEX="^Apple TV"
    ;;
  visionos)
    PLATFORM_LABEL="visionOS"
    RUNTIME_PREFIX="visionOS"
    DEVICE_REGEX="^Apple Vision"
    ;;
  *)
    echo "Unsupported platform input: ${PLATFORM_RAW}"
    echo "Expected one of: ios, tvos, visionos, macos"
    exit 1
    ;;
esac

# Resolve the runtime and the device type together. A device type listed by
# `simctl list devicetypes` is not necessarily supported by the runtime we pick,
# and `simctl create` rejects an incompatible pair.
SELECTION="$(
  python3 "${ACTION_PATH}/select-simulator.py" "${RUNTIME_PREFIX}" "${DEVICE_REGEX}"
)"

IFS=$'\t' read -r RUNTIME_ID RUNTIME_LABEL DEVICE_TYPE DEVICE_NAME SIM_ID <<< "${SELECTION}"

echo "Selected ${DEVICE_NAME} on ${RUNTIME_LABEL}"

SIM_NAME="Statsig-CI-${PLATFORM_LABEL}"

if [ -n "${SIM_ID}" ]; then
  echo "Using existing simulator ${DEVICE_NAME} (${SIM_ID}) in ${RUNTIME_LABEL}"
else
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
