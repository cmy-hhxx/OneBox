#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
repository_root=${script_directory:h}
artifact_root="$repository_root/.build"
package_path="$repository_root/Packages/Tools/AsciiArtTool"
scratch_path="$artifact_root/SwiftPM/AsciiArtTool"
run_id=${ONEBOX_BENCHMARK_RUN_ID:-"$(date +%Y%m%d-%H%M%S)-$$"}
log_path="$artifact_root/Logs/ascii-benchmark-$run_id.log"
report_path="$artifact_root/Logs/ascii-benchmark-$run_id.json"
rerun_log_path="$artifact_root/Logs/ascii-benchmark-$run_id-rerun.log"
rerun_report_path="$artifact_root/Logs/ascii-benchmark-$run_id-rerun.json"
configured_baseline=${ONEBOX_ASCII_BENCHMARK_BASELINE:-}
conventional_baseline="$repository_root/Benchmarks/Baselines/ascii.json"
baseline_path=$configured_baseline
rerun_performed=false

if [[ "$(uname -m)" != "arm64" ]]; then
    print -u2 "Apple Silicon (arm64) is required to run the ASCII benchmark."
    exit 2
fi

mkdir -p "$artifact_root/Logs" "$scratch_path"
set -o pipefail

if [[ -n "$configured_baseline" && ! -f "$configured_baseline" ]]; then
    print -u2 "Configured ASCII benchmark baseline does not exist: $configured_baseline"
    exit 2
fi

if [[ -z "$baseline_path" && -f "$conventional_baseline" ]]; then
    baseline_path=$conventional_baseline
fi

if [[ -n "$baseline_path" ]]; then
    "$script_directory/compare-benchmark-report.sh" "$baseline_path" "$baseline_path" >/dev/null || {
        print -u2 "Configured ASCII benchmark baseline is invalid: $baseline_path"
        exit 2
    }
    jq -e '.benchmark == "ASCII"' "$baseline_path" >/dev/null || {
        print -u2 "Configured baseline is not an ASCII benchmark report: $baseline_path"
        exit 2
    }
fi

run_benchmark() {
    local destination_log=$1
    local destination_report=$2
    local test_status=0
    local report_status=0

    xcrun swift test \
        --package-path "$package_path" \
        --scratch-path "$scratch_path" \
        --configuration release \
        --filter AsciiPerformanceTests \
        2>&1 | tee "$destination_log" || test_status=$?

    "$script_directory/write-benchmark-report.sh" "ASCII" "$destination_log" "$destination_report" || report_status=$?

    if (( test_status != 0 )); then
        return 1
    fi
    if (( report_status != 0 )); then
        return 2
    fi
    return 0
}

evaluation_failure_kind=""
evaluation_failure_status=0

evaluate_benchmark() {
    local destination_log=$1
    local destination_report=$2
    local benchmark_status=0
    local comparison_status=0

    evaluation_failure_kind=""
    evaluation_failure_status=0

    run_benchmark "$destination_log" "$destination_report" || benchmark_status=$?
    if (( benchmark_status == 1 )); then
        evaluation_failure_kind="measured benchmark"
        evaluation_failure_status=1
        return 1
    fi
    if (( benchmark_status != 0 )); then
        evaluation_failure_kind="benchmark report schema"
        evaluation_failure_status=2
        return 2
    fi

    if [[ -n "$baseline_path" ]]; then
        "$script_directory/compare-benchmark-report.sh" "$baseline_path" "$destination_report" || comparison_status=$?
        if (( comparison_status == 1 )); then
            evaluation_failure_kind="relative regression gate"
            evaluation_failure_status=$comparison_status
            return 1
        fi
        if (( comparison_status != 0 )); then
            evaluation_failure_kind="baseline configuration"
            evaluation_failure_status=$comparison_status
            return 2
        fi
    fi

    return 0
}

if [[ -z "$baseline_path" ]]; then
    print "No ASCII benchmark baseline configured; relative regression comparison skipped."
    print "Set ONEBOX_ASCII_BENCHMARK_BASELINE or add $conventional_baseline to enable it."
fi

if evaluate_benchmark "$log_path" "$report_path"; then
    :
else
    evaluation_status=$?
    first_failure_kind=$evaluation_failure_kind
    first_failure_status=$evaluation_failure_status

    if (( evaluation_status == 2 )); then
        exit "$first_failure_status"
    fi

    print -u2 "ASCII benchmark first run failed ($first_failure_kind, exit $first_failure_status); rerunning the full benchmark once."
    rerun_performed=true

    if evaluate_benchmark "$rerun_log_path" "$rerun_report_path"; then
        print "ASCII benchmark rerun passed; the first failure is treated as noise."
    else
        evaluation_status=$?
        second_failure_kind=$evaluation_failure_kind
        second_failure_status=$evaluation_failure_status

        if (( evaluation_status == 2 )); then
            exit "$second_failure_status"
        fi

        print -u2 "ASCII benchmark failed on both full runs."
        print -u2 "First failure: $first_failure_kind (exit $first_failure_status)"
        print -u2 "Second failure: $second_failure_kind (exit $second_failure_status)"
        print -u2 "First log: $log_path"
        print -u2 "First report: $report_path"
        print -u2 "Rerun log: $rerun_log_path"
        print -u2 "Rerun report: $rerun_report_path"
        exit "$second_failure_status"
    fi
fi

print "Benchmark log: $log_path"
print "Benchmark report: $report_path"
if [[ "$rerun_performed" == true ]]; then
    print "Rerun log: $rerun_log_path"
    print "Rerun report: $rerun_report_path"
fi
