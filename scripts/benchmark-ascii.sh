#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
repository_root=${script_directory:h}
artifact_root="$repository_root/.build"

"$script_directory/bootstrap.sh"

xcodebuild \
    -project "$repository_root/OneBox.xcodeproj" \
    -scheme AsciiArtBenchmark \
    -configuration Release \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$artifact_root/DerivedData-Release" \
    -only-testing:AsciiArtToolTests/AsciiPerformanceTests \
    ENABLE_TESTABILITY=YES \
    CODE_SIGNING_ALLOWED=NO \
    test
