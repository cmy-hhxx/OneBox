#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
repository_root=${script_directory:h}
artifact_root="$repository_root/.build"
run_id="$(date +%Y%m%d-%H%M%S)-$$"
log_path="$artifact_root/Logs/test-$run_id.log"
result_path="$artifact_root/TestResults/OneBox-$run_id.xcresult"

"$script_directory/bootstrap.sh"

cd "$artifact_root"
set -o pipefail
xcodebuild \
    -project "$repository_root/OneBox.xcodeproj" \
    -scheme OneBox \
    -configuration Debug \
    -derivedDataPath "$artifact_root/DerivedData" \
    -resultBundlePath "$result_path" \
    CODE_SIGNING_ALLOWED=NO \
    test 2>&1 | tee "$log_path"

print "Test log: $log_path"
print "Test result: $result_path"
