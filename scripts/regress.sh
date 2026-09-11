#!/bin/zsh
# Isolated native regression. No uninstall/reset, no access to the personal ledger.
set -euo pipefail
cd "${0:A:h:h}"
task_mode="${1:-core}"
task_device="${2:-}"
task_build="${YUJI_REGRESSION_BUILD:-.build-regression}"
task_output="${YUJI_REGRESSION_OUTPUT:-evidence/regression-$(date +%Y%m%d-%H%M%S)-$(uuidgen)}"
task_build="${task_build:A}"
task_output="${task_output:A}"
mkdir -p "$task_output"
case "$task_mode" in
  core) swift test 2>&1 | tee "$task_output/core.log" ;;
  build)
    [[ -n "$task_device" ]] || { print -u2 'Usage: scripts/regress.sh build SIMULATOR_UUID'; exit 2; }
    xcodegen generate --spec ios-app/project.yml
    xcodebuild build-for-testing -project ios-app/Yuji.xcodeproj -scheme Yuji -destination "platform=iOS Simulator,id=$task_device" -derivedDataPath "$task_build" CODE_SIGNING_ALLOWED=NO > "$task_output/build.log" 2>&1 ;;
  test)
    [[ -n "$task_device" ]] || { print -u2 'Usage: scripts/regress.sh test SIMULATOR_UUID [xcodebuild test filters]'; exit 2; }
    task_manifests=("$task_build"/Build/Products/Yuji_*.xctestrun(N))
    (( ${#task_manifests} == 1 )) || { print -u2 'Build first; expected one xctestrun manifest.'; exit 2; }
    # Per-run manifest prevents another simulator run from changing this host environment.
    task_manifest="$task_build/Build/Products/regression-$(uuidgen).xctestrun"
    cp "$task_manifests[1]" "$task_manifest"
    trap 'rm -f "$task_manifest"' EXIT
    /usr/libexec/PlistBuddy -c 'Delete :YujiTests:EnvironmentVariables:YUJI_STRESS_SESSION' "$task_manifest" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :YujiTests:EnvironmentVariables:YUJI_STRESS_SESSION string $(uuidgen)" "$task_manifest"
    /usr/libexec/PlistBuddy -c 'Delete :YujiTests:EnvironmentVariables:YUJI_TEST_TODAY' "$task_manifest" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c 'Add :YujiTests:EnvironmentVariables:YUJI_TEST_TODAY string 2026-09-10' "$task_manifest"
    shift 2
    xcodebuild test-without-building -xctestrun "$task_manifest" -parallel-testing-enabled NO -destination "platform=iOS Simulator,id=$task_device" -resultBundlePath "$task_output/results.xcresult" "$@" > "$task_output/native.log" 2>&1 ;;
  release)
    xcodegen generate --spec ios-app/project.yml
    xcodebuild build -project ios-app/Yuji.xcodeproj -scheme Yuji -configuration Release -destination 'generic/platform=iOS' -derivedDataPath "${task_build}-release" CODE_SIGNING_ALLOWED=NO > "$task_output/release.log" 2>&1 ;;
  *) print -u2 'Modes: core, build SIMULATOR_UUID, test SIMULATOR_UUID [filters], release'; exit 2 ;;
esac
print "Results: $task_output"
