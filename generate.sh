#!/bin/bash
# Generates the Xcode project for the iPhone app. Optional first: cp Config/local.env.example Config/local.env and fill it in.
set -euo pipefail
cd "$(dirname "$0")"
command -v xcodegen >/dev/null || { echo "XcodeGen is required: brew install xcodegen"; exit 1; }
if [ -f Config/local.env ]; then
  # shellcheck disable=SC1091
  source Config/local.env
else
  echo "No Config/local.env: using the default bundle ID (pick your team in Xcode > Signing & Capabilities)"
fi
export FACECONTROLLER_TEAM_ID="${FACECONTROLLER_TEAM_ID:-}"
export FACECONTROLLER_BUNDLE_ID="${FACECONTROLLER_BUNDLE_ID:-com.example.facecontroller}"
xcodegen generate
echo "Done: FaceController.xcodeproj (bundle ID $FACECONTROLLER_BUNDLE_ID)"
