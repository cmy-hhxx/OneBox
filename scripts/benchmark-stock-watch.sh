#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
repository_root=${script_directory:h}
artifact_root="$repository_root/.build"
package_path="$repository_root/Packages/Tools/StockWatchTool"
scratch_path="$artifact_root/SwiftPM/StockWatchTool"
run_id="$(date +%Y%m%d-%H%M%S)-$$"
log_path="$artifact_root/Logs/stock-watch-benchmark-$run_id.log"

if [[ "$(uname -m)" != "arm64" ]]; then
    print -u2 "Apple Silicon (arm64) is required to run the stock watch benchmark."
    exit 1
fi

mkdir -p "$artifact_root/Logs" "$scratch_path"
set -o pipefail
xcrun swift test \
    --package-path "$package_path" \
    --scratch-path "$scratch_path" \
    --configuration release \
    --traits Benchmark \
    --filter 'StockWatchPerformanceTests\.' \
    2>&1 | tee "$log_path"

print "Benchmark log: $log_path"
