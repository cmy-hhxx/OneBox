#!/bin/zsh

set -euo pipefail

if (( $# != 3 )); then
    print -u2 "usage: $0 <benchmark-name> <log-path> <report-path>"
    exit 64
fi

benchmark_name=$1
log_path=$2
report_path=$3
script_directory=${0:A:h}
repository_root=${script_directory:h}

if [[ ! -f "$log_path" ]]; then
    print -u2 "Benchmark log does not exist: $log_path"
    exit 2
fi

git_sha=$(git -C "$repository_root" rev-parse HEAD)
hardware_json=$(system_profiler SPHardwareDataType -json 2>/dev/null || print '{}')
cpu_name=$(
    sysctl -n machdep.cpu.brand_string 2>/dev/null \
        || jq -r '.SPHardwareDataType[0].chip_type // "unknown"' <<< "$hardware_json"
)
memory_bytes=$(
    sysctl -n hw.memsize 2>/dev/null \
        || jq -r '
            .SPHardwareDataType[0].physical_memory? // ""
            | capture("^(?<value>[0-9.]+)\\s*(?<unit>[KMGT]B)$")?
            | if . == null then 0
              elif .unit == "KB" then (.value | tonumber) * 1024
              elif .unit == "MB" then (.value | tonumber) * 1048576
              elif .unit == "GB" then (.value | tonumber) * 1073741824
              elif .unit == "TB" then (.value | tonumber) * 1099511627776
              else 0
              end
          ' <<< "$hardware_json"
)
memory_bytes=${memory_bytes%.*}
macos_version=$(sw_vers -productVersion)
xcode_version=$(xcodebuild -version | paste -sd ' ' -)
thermal_state=$(pmset -g therm 2>/dev/null | tr '\n' ' ' || print "unavailable")
display_refresh_rate_value=$(
    system_profiler SPDisplaysDataType -json 2>/dev/null \
        | jq -r '
            [.. | objects | .spdisplays_refreshRate? // empty][0] // ""
            | capture("(?<hz>[0-9]+(?:[.][0-9]+)?)")?.hz // ""
          ' \
        || true
)
if [[ -z "$display_refresh_rate_value" ]] \
    || ! jq -e 'tonumber? != null and tonumber > 0' <<< "$display_refresh_rate_value" >/dev/null; then
    module_cache_path="$repository_root/.build/BenchmarkModuleCache"
    mkdir -p "$module_cache_path"
    display_refresh_rate_value=$(
        xcrun swift -module-cache-path "$module_cache_path" -e '
            import AppKit
            let framesPerSecond = NSScreen.main?.maximumFramesPerSecond ?? 0
            if framesPerSecond > 0 { print(framesPerSecond) }
          ' 2>/dev/null \
            || true
    )
fi
if [[ -z "$display_refresh_rate_value" ]] \
    || ! jq -e 'tonumber? != null and tonumber > 0' <<< "$display_refresh_rate_value" >/dev/null; then
    print -u2 "Could not determine a positive display refresh rate."
    exit 2
fi
display_refresh_rate="${display_refresh_rate_value} Hz"

report_directory=${report_path:h}
report_filename=${report_path:t}
mkdir -p "$report_directory"
temporary_report=$(mktemp "$report_directory/.${report_filename}.XXXXXX")
trap 'rm -f "$temporary_report"' EXIT

if ! jq -n \
    --arg benchmark "$benchmark_name" \
    --arg git_sha "$git_sha" \
    --arg architecture "$(uname -m)" \
    --arg cpu "$cpu_name" \
    --argjson memory_bytes "$memory_bytes" \
    --arg macos "$macos_version" \
    --arg xcode "$xcode_version" \
    --arg display_refresh_rate "$display_refresh_rate" \
    --arg thermal_state "$thermal_state" \
    --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --rawfile log "$log_path" '
        def median($values):
            ($values | sort) as $sorted
            | ($sorted | length) as $count
            | if $count == 0 then null
              elif ($count % 2) == 1 then $sorted[($count / 2 | floor)]
              else (($sorted[$count / 2 - 1] + $sorted[$count / 2]) / 2)
              end;
        def percentile95($values):
            ($values | sort) as $sorted
            | if ($sorted | length) == 0 then null
              else $sorted[((($sorted | length) * 0.95 | ceil) - 1)]
              end;
        [
            $log
            | split("\n")[]
            | select(test(" measured \\["))
            | capture(
                "Test Case (?<test>.*) measured \\[(?<metric>[^\\]]+)\\] average: (?<average>[0-9.eE+-]+).*values: \\[(?<raw_values>[^\\]]*)\\]"
              )?
            | select(. != null)
            | (.raw_values | split(",") | map(gsub("^\\s+|\\s+$"; "") | tonumber)) as $values
            | {
                test,
                metric,
                average: (.average | tonumber),
                median: median($values),
                p95: percentile95($values),
                max: ($values | max),
                samples: $values
              }
        ] as $measurements
        | {
            schemaVersion: 1,
            benchmark: $benchmark,
            generatedAt: $generated_at,
            gitSHA: $git_sha,
            environment: {
                architecture: $architecture,
                cpu: $cpu,
                memoryBytes: $memory_bytes,
                macOS: $macos,
                Xcode: $xcode,
                displayRefreshRate: $display_refresh_rate,
                thermalState: $thermal_state
              },
            measurements: $measurements
          }
    ' > "$temporary_report"; then
    print -u2 "Could not parse benchmark measurements from: $log_path"
    exit 2
fi

if ! jq -e '
    def is_positive_refresh_rate:
        type == "string"
        and test("^[0-9]+(?:[.][0-9]+)? Hz$")
        and ((capture("^(?<hz>[0-9]+(?:[.][0-9]+)?) Hz$").hz | tonumber) > 0);

    (.schemaVersion == 1)
    and (.benchmark | type == "string" and length > 0)
    and (.environment | type == "object")
    and (.environment.architecture | type == "string" and length > 0)
    and (.environment.cpu | type == "string" and length > 0)
    and (.environment.memoryBytes | type == "number" and . > 0)
    and (.environment.macOS | type == "string" and length > 0)
    and (.environment.Xcode | type == "string" and length > 0)
    and (.environment.displayRefreshRate | is_positive_refresh_rate)
    and (.measurements | type == "array")
    and all(.measurements[];
        (.test | type == "string" and length > 0)
        and (.metric | type == "string" and length > 0)
        and (.average | type == "number")
        and (.median | type == "number")
        and (.p95 | type == "number")
        and (.max | type == "number")
        and (.samples | type == "array")
        and all(.samples[]; type == "number")
    )
  ' "$temporary_report" >/dev/null; then
    print -u2 "Generated benchmark report has an invalid schema: $log_path"
    exit 2
fi

measurement_count=$(jq -r '.measurements | length' "$temporary_report")
if (( measurement_count == 0 )); then
    print -u2 "Benchmark log contains no parsed measurement series: $log_path"
    exit 2
fi

if ! jq -e 'any(.measurements[]; .metric == "Clock Monotonic Time, s")' "$temporary_report" >/dev/null; then
    print -u2 "Benchmark report contains no Clock Monotonic Time measurement: $log_path"
    exit 2
fi

short_series=$(
    jq -r '
        .measurements[]
        | select((.samples | length) < 30)
        | "\(.test) — \(.metric): \(.samples | length) samples"
      ' "$temporary_report"
)
if [[ -n "$short_series" ]]; then
    print -u2 "Benchmark measurement series must contain at least 30 samples:"
    print -u2 -- "$short_series"
    exit 2
fi

duplicate_count=$(
    jq -r '
        [.measurements[] | [.test, .metric] | @json]
        | (length - (unique | length))
      ' "$temporary_report"
)
if (( duplicate_count != 0 )); then
    print -u2 "Benchmark report contains duplicate test/metric measurement series."
    exit 2
fi

chmod 0644 "$temporary_report"
mv "$temporary_report" "$report_path"
trap - EXIT
