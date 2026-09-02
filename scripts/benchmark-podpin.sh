#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
repository_root=${script_directory:h}
artifact_root="$repository_root/.build"
package_path="$repository_root/Packages/Tools/PodPinTool"
scratch_path="$artifact_root/SwiftPM/PodPinTool"
run_id="$(date +%Y%m%d-%H%M%S)-$$"
log_path="$artifact_root/Logs/podpin-benchmark-$run_id.log"

if [[ "$(uname -m)" != "arm64" ]]; then
    print -u2 "Apple Silicon (arm64) is required to run the PodPin benchmark."
    exit 1
fi

mkdir -p "$artifact_root/Logs" "$scratch_path"
set -o pipefail
xcrun swift test \
    --package-path "$package_path" \
    --scratch-path "$scratch_path" \
    --configuration release \
    --traits Benchmark \
    --traits Testing \
    --filter 'PodPinPerformanceTests.WorkspacePerformanceTests/' \
    2>&1 | tee "$log_path"

print "Benchmark log: $log_path"
