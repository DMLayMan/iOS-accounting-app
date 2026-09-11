#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
SIMULATOR_ID="${1:-7D938105-A3A8-464A-A083-2195BEC29F0E}"
xcodegen generate --spec ios-app/project.yml
xcodebuild -project ios-app/Yuji.xcodeproj -scheme Yuji -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath .build-ios CODE_SIGNING_ALLOWED=NO build
# Boot only if the selected simulator is not already booted.
SIMULATOR_STATE=$(xcrun simctl list devices --json | /usr/bin/plutil -extract devices json -o - - | \
  /usr/bin/awk -v id="$SIMULATOR_ID" 'BEGIN { RS="}," } index($0,id) { print }')
if [[ "$SIMULATOR_STATE" != *'"Booted"'* ]]; then
  xcrun simctl boot "$SIMULATOR_ID"
fi
xcrun simctl bootstatus "$SIMULATOR_ID" -b
xcrun simctl install "$SIMULATOR_ID" .build-ios/Build/Products/Debug-iphonesimulator/Yuji.app
xcrun simctl launch "$SIMULATOR_ID" com.yuji.app -AppleLanguages '(zh-Hans)' -AppleLocale zh_CN
