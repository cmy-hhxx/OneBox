#!/bin/zsh

set -euo pipefail

if (( $# > 1 )); then
    print -u2 "usage: $0 [--podpin-live|--podpin-live-downloads]"
    exit 64
fi

test_mode="${1:-default}"
case "$test_mode" in
    default)
        live_imports=""
        live_downloads=""
        ;;
    --podpin-live)
        live_imports="YES"
        live_downloads=""
        ;;
    --podpin-live-downloads)
        live_imports="YES"
        live_downloads="YES"
        ;;
    *)
        print -u2 "usage: $0 [--podpin-live|--podpin-live-downloads]"
        exit 64
        ;;
esac

script_directory=${0:A:h}
repository_root=${script_directory:h}
artifact_root="$repository_root/.build"
host_architecture="$(uname -m)"
run_id="$(date +%Y%m%d-%H%M%S)-$$"
log_path="$artifact_root/Logs/test-$run_id.log"
result_directory="$artifact_root/TestResults/OneBox-$run_id"
products_root="$artifact_root/DerivedData/Build/Products"
swiftpm_root="$artifact_root/SwiftPM"
ffmpeg_path=""
ffprobe_path=""

run_swift_package_tests() {
    local package_name=$1
    local package_path=$2
    shift 2
    local scratch_path="$swiftpm_root/$package_name"
    local target_log="$result_directory/$package_name.log"
    local coverage_output="$result_directory/$package_name-coverage.json"
    local coverage_path

    print "Building and testing $package_name"
    {
        xcrun swift build \
            --package-path "$package_path" \
            --scratch-path "$scratch_path"
        xcrun swift test \
            --package-path "$package_path" \
            --scratch-path "$scratch_path" \
            --enable-code-coverage \
            "$@"
    } 2>&1 | tee "$target_log"

    coverage_path="$(
        xcrun swift test \
            --package-path "$package_path" \
            --scratch-path "$scratch_path" \
            --show-codecov-path
    )"
    if [[ ! -f "$coverage_path" ]]; then
        print -u2 "No coverage report produced for $package_name."
        exit 1
    fi
    jq -e --arg source_root "$package_path/Sources/" \
        '[.data[].files[].filename | select(startswith($source_root))] | length > 0' \
        "$coverage_path" >/dev/null || {
        print -u2 "Coverage report does not contain package sources for $package_name."
        exit 1
    }
    cp "$coverage_path" "$coverage_output"
}
if [[ "$live_downloads" == "YES" ]]; then
    tool_lock="$repository_root/Tools/tool-lock.json"
    ffmpeg_relative_path="$(jq -er '.tools[] | select(.name == "ffmpeg") | .preparedCacheFile' "$tool_lock")"
    ffprobe_relative_path="$(jq -er '.tools[] | select(.name == "ffprobe") | .preparedCacheFile' "$tool_lock")"
    ffmpeg_path="$repository_root/Tools/cache/$ffmpeg_relative_path"
    ffprobe_path="$repository_root/Tools/cache/$ffprobe_relative_path"
fi

"$script_directory/bootstrap.sh"

# Offline-tool packaging re-signs the local app. Remove that disposable bundle
# so a later test build cannot mix its signature with XCTest products.
rm -rf "$products_root/Debug/OneBox.app"
rm -f "$products_root"/OneBox_*.xctestrun(N)
mkdir -p "$result_directory" "$swiftpm_root"

cd "$artifact_root"
set -o pipefail
{
    if [[ "$live_downloads" == "YES" ]]; then
        "$script_directory/fetch-podpin-tools.sh"
    fi

    if [[ "$test_mode" == "default" ]]; then
        run_swift_package_tests \
            OneBoxCore \
            "$repository_root/Packages/OneBoxCore"
    fi

    xcodebuild \
        -project "$repository_root/OneBox.xcodeproj" \
        -scheme OneBox \
        -configuration Debug \
        -destination "platform=macOS,arch=$host_architecture" \
        -derivedDataPath "$artifact_root/DerivedData" \
        build-for-testing

    xctestrun_files=("$products_root"/OneBox_*.xctestrun(N))
    if (( ${#xctestrun_files} != 1 )); then
        print -u2 "Expected one generated .xctestrun, found ${#xctestrun_files}."
        exit 1
    fi
    xctestrun_path=${xctestrun_files[1]}
    patched_json="$(mktemp "$artifact_root/xctestrun.json.XXXXXX")"
    trap 'rm -f "$patched_json"' EXIT

    # Xcode 26.6 prepends its intermediate PackageFrameworks directory when it
    # launches a macOS test host. dyld can block on that intermediate GRDB
    # wrapper. Its injected runtime checkers can also block while loading the
    # test bundle. The IDE keeps those diagnostics for normal launches; this
    # deterministic CLI run loads the app-owned framework without the checkers.
    plutil -convert json -o - "$xctestrun_path" \
        | jq --arg live_imports "$live_imports" \
            --arg live_downloads "$live_downloads" 'walk(
            if type == "object" then
                (if has("DYLD_FRAMEWORK_PATH") then
                    .DYLD_FRAMEWORK_PATH |= (
                        split(":")
                        | map(select(contains("/PackageFrameworks") | not))
                        | ["__TESTHOST__/Contents/Frameworks"] + .
                        | join(":")
                    )
                else . end)
                | (if has("DYLD_INSERT_LIBRARIES") then
                    .DYLD_INSERT_LIBRARIES |= (
                        split(":")
                        | map(select(
                            (contains("libRPAC.dylib")
                                or contains("libMainThreadChecker.dylib"))
                            | not
                        ))
                        | join(":")
                    )
                else . end)
                | (if has("EnvironmentVariables") and $live_imports == "YES" then
                    .EnvironmentVariables.PODPIN_RUN_LIVE_IMPORTS = "YES"
                else . end)
                | (if has("EnvironmentVariables") and $live_downloads == "YES" then
                    .EnvironmentVariables.PODPIN_RUN_LIVE_DOWNLOADS = "YES"
                else . end)
            else . end
        )' > "$patched_json"
    plutil -convert binary1 -o "$xctestrun_path" "$patched_json"

    if [[ "$test_mode" == "default" ]]; then
        hostless_test_targets=(
            AsciiArtToolTests
            StockWatchToolTests
            PodPinToolTests
        )
        hosted_test_targets=(OneBoxAppTests)
    else
        hostless_test_targets=(PodPinToolTests)
        hosted_test_targets=()
    fi
    for test_target in "${hostless_test_targets[@]}"; do
        print "Running $test_target"
        test_bundle="$products_root/Debug/$test_target.xctest"
        test_binary="$test_bundle/Contents/MacOS/$test_target"
        profile_pattern="$result_directory/$test_target-%p.profraw"
        target_log="$result_directory/$test_target.log"
        PODPIN_RUN_LIVE_IMPORTS="$live_imports" \
            PODPIN_RUN_LIVE_DOWNLOADS="$live_downloads" \
            PODPIN_FFMPEG_PATH="$ffmpeg_path" \
            PODPIN_FFPROBE_PATH="$ffprobe_path" \
            LLVM_PROFILE_FILE="$profile_pattern" \
            xcrun xctest "$test_bundle" 2>&1 | tee "$target_log"

        profile_files=("$result_directory"/$test_target-*.profraw(N))
        if (( ${#profile_files} == 0 )); then
            print -u2 "No coverage profile produced for $test_target."
            exit 1
        fi
        profile_data="$result_directory/$test_target.profdata"
        xcrun llvm-profdata merge -sparse "${profile_files[@]}" -o "$profile_data"
        xcrun llvm-cov report "$test_binary" -instr-profile="$profile_data" \
            > "$result_directory/$test_target-coverage.txt"
        rm -f "${profile_files[@]}"
    done

    for test_target in "${hosted_test_targets[@]}"; do
        print "Running $test_target"
        xcodebuild \
            -xctestrun "$xctestrun_path" \
            -destination "platform=macOS,arch=$host_architecture" \
            -parallel-testing-enabled NO \
            -only-testing:"$test_target" \
            -resultBundlePath "$result_directory/$test_target.xcresult" \
            test-without-building
    done
} 2>&1 | tee "$log_path"

print "Test log: $log_path"
print "Test results: $result_directory"
