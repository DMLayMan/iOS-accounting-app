#!/bin/zsh
# Builds the native app and opens an isolated 500-record ledger. Never uninstalls the app.
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
task_device="${1:-7D938105-A3A8-464A-A083-2195BEC29F0E}"
task_session="$(uuidgen)"
xcodegen generate --spec ios-app/project.yml
xcodebuild -project ios-app/Yuji.xcodeproj -scheme Yuji -configuration Debug -destination "platform=iOS Simulator,id=$task_device" -derivedDataPath .build-ios build > evidence/stats-500/preview-build.log 2>&1
xcrun simctl boot "$task_device" 2>/dev/null || true
xcrun simctl bootstatus "$task_device" -b
xcrun simctl install "$task_device" .build-ios/Build/Products/Debug-iphonesimulator/Yuji.app
xcrun simctl terminate "$task_device" com.yuji.app 2>/dev/null || true
SIMCTL_CHILD_YUJI_STRESS_SESSION="$task_session" SIMCTL_CHILD_YUJI_STRESS_PREVIEW=1 xcrun simctl launch "$task_device" com.yuji.app
printf '%s\n' "$task_session" > evidence/stats-500/preview-session.txt
open -a Simulator
