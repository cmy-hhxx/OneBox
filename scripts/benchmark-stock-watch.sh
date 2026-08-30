#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
repository_root=${script_directory:h}
artifact_root="$repository_root/.build"

if [[ "$(uname -m)" != "arm64" ]]; then
    print -u2 "Apple Silicon (arm64) is required to run the stock watch benchmark."
    exit 1
fi

"$script_directory/bootstrap.sh"

xcodebuild \
    -project "$repository_root/OneBox.xcodeproj" \
    -scheme StockWatchBenchmark \
    -configuration Release \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$artifact_root/DerivedData-StockWatch-Release" \
    -only-testing:StockWatchPerformanceTests \
    ENABLE_TESTABILITY=YES \
    CODE_SIGNING_ALLOWED=NO \
    test
