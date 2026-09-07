#!/bin/zsh

set -euo pipefail

if (( $# != 2 )); then
    print -u2 "usage: $0 <baseline.xcresult> <candidate.xcresult>"
    exit 64
fi

baseline_path=$1
candidate_path=$2

for result_path in "$baseline_path" "$candidate_path"; do
    if [[ ! -d "$result_path" ]]; then
        print -u2 "UI performance result bundle does not exist: $result_path"
        exit 2
    fi
done

read_summary() {
    xcrun xcresulttool get test-results summary \
        --schema-version 0.1.0 \
        --path "$1" \
        --compact
}

read_metrics() {
    xcrun xcresulttool get test-results metrics \
        --schema-version 0.1.0 \
        --path "$1" \
        --compact
}

baseline_summary=$(read_summary "$baseline_path")
candidate_summary=$(read_summary "$candidate_path")
baseline_metrics=$(read_metrics "$baseline_path")
candidate_metrics=$(read_metrics "$candidate_path")

validate_summary() {
    local label=$1
    local summary=$2

    if ! jq -e '
        type == "object"
        and .result == "Passed"
        and (.devicesAndConfigurations | type == "array" and length == 1)
        and all(.devicesAndConfigurations[];
            (.testPlanConfiguration.configurationName | type == "string" and length > 0)
            and (.device.deviceId | type == "string" and length > 0)
            and (.device.architecture | type == "string" and length > 0)
            and (.device.modelName | type == "string" and length > 0)
            and (.device.osVersion | type == "string" and length > 0)
            and (.device.osBuildNumber | type == "string" and length > 0)
        )
      ' <<< "$summary" >/dev/null; then
        print -u2 "Invalid $label UI performance summary."
        return 2
    fi
}

normalize_metrics() {
    jq -c '
        def is_peak_physical_memory:
            (.identifier // "") == "com.apple.dt.XCTMetric_Memory.physical_peak"
            or (.displayName | startswith("Memory Peak Physical"));
        def is_time:
            .unitOfMeasurement == "s"
            or .unitOfMeasurement == "ms"
            or .unitOfMeasurement == "us"
            or .unitOfMeasurement == "ns";
        def median($values):
            ($values | sort) as $sorted
            | ($sorted | length) as $count
            | if ($count % 2) == 1 then
                $sorted[($count / 2 | floor)]
              else
                (($sorted[$count / 2 - 1] + $sorted[$count / 2]) / 2)
              end;
        def percentile95($values):
            ($values | sort) as $sorted
            | $sorted[((($sorted | length) * 0.95 | ceil) - 1)];

        [
            .[] as $test
            | $test.testRuns[] as $run
            | $run.metrics[]
            | select(is_time or is_peak_physical_memory)
            | {
                test: $test.testIdentifier,
                configuration: $run.testPlanConfiguration.configurationName,
                metricIdentifier: (.identifier // .displayName),
                metric: .displayName,
                unit: .unitOfMeasurement,
                kind: (if is_peak_physical_memory then "memory" else "time" end),
                samples: .measurements,
                median: median(.measurements),
                p95: percentile95(.measurements),
                max: (.measurements | max),
                minimumSampleCount: (
                    if ($test.testIdentifier | contains("testColdLaunch")) then 10 else 30 end
                )
              }
        ]
      '
}

validate_summary "baseline" "$baseline_summary" || exit 2
validate_summary "candidate" "$candidate_summary" || exit 2

baseline_normalized=$(normalize_metrics <<< "$baseline_metrics")
candidate_normalized=$(normalize_metrics <<< "$candidate_metrics")

validate_metrics() {
    local label=$1
    local metrics=$2

    if ! jq -e '
        type == "array"
        and length > 0
        and any(.[]; .kind == "time")
        and any(.[]; .kind == "memory")
        and all(.[];
            (.test | type == "string" and length > 0)
            and (.configuration | type == "string" and length > 0)
            and (.metricIdentifier | type == "string" and length > 0)
            and (.metric | type == "string" and length > 0)
            and (.unit | type == "string" and length > 0)
            and (.samples | type == "array")
            and ((.samples | length) >= .minimumSampleCount)
            and all(.samples[]; type == "number")
            and (.median | type == "number" and . > 0)
            and (.p95 | type == "number" and . > 0)
            and (.max | type == "number" and . > 0)
        )
        and (
            ([.[] | [.test, .configuration, .metricIdentifier, .metric, .unit] | @json] | length)
            == ([.[] | [.test, .configuration, .metricIdentifier, .metric, .unit] | @json] | unique | length)
        )
      ' <<< "$metrics" >/dev/null; then
        print -u2 "Invalid $label UI performance metrics (expected unique time and peak-memory series with 10 cold-launch or 30 warmed samples)."
        return 2
    fi
}

validate_metrics "baseline" "$baseline_normalized" || exit 2
validate_metrics "candidate" "$candidate_normalized" || exit 2

comparison=$(
    jq -n \
        --argjson baselineSummary "$baseline_summary" \
        --argjson candidateSummary "$candidate_summary" \
        --argjson baseline "$baseline_normalized" \
        --argjson candidate "$candidate_normalized" '
        def metric_key:
            [.test, .configuration, .metricIdentifier, .metric, .unit] | @json;
        def percent_regression($before; $after):
            (($after - $before) / $before * 100);
        def memory_mib($unit; $value):
            if $unit == "kB" or $unit == "KB" then $value / 1024
            elif $unit == "bytes" or $unit == "B" then $value / 1048576
            elif $unit == "MiB" or $unit == "MB" then $value
            else null
            end;
        def environment($summary):
            $summary.devicesAndConfigurations
            | map({
                configuration: .testPlanConfiguration.configurationName,
                deviceId: .device.deviceId,
                architecture: .device.architecture,
                modelName: .device.modelName,
                platform: (.device.platform // ""),
                osVersion: .device.osVersion,
                osBuildNumber: .device.osBuildNumber
              });

        ($baseline | map({key: metric_key, value: .}) | from_entries) as $baselineByKey
        | ($candidate | map({key: metric_key, value: .}) | from_entries) as $candidateByKey
        | [
            $baseline[]
            | (metric_key) as $key
            | select($candidateByKey[$key] == null)
            | {test, metric, unit}
          ] as $missingMetrics
        | [
            $candidate[]
            | (metric_key) as $key
            | select($baselineByKey[$key] == null)
            | {test, metric, unit}
          ] as $unbaselinedMetrics
        | [
            $baseline[] as $previous
            | ($previous | metric_key) as $key
            | $candidateByKey[$key] as $current
            | select($current != null)
            | if $current.kind == "time" then
                (
                    if ($current.median / $previous.median) > 1.10 then
                        {
                            test: $current.test,
                            metric: $current.metric,
                            statistic: "median",
                            baseline: $previous.median,
                            candidate: $current.median,
                            regressionPercent: percent_regression($previous.median; $current.median),
                            limit: "10%"
                        }
                    else empty end
                ),
                (
                    if ($current.p95 / $previous.p95) > 1.15 then
                        {
                            test: $current.test,
                            metric: $current.metric,
                            statistic: "p95",
                            baseline: $previous.p95,
                            candidate: $current.p95,
                            regressionPercent: percent_regression($previous.p95; $current.p95),
                            limit: "15%"
                        }
                    else empty end
                )
              else
                (memory_mib($current.unit; $current.max) - memory_mib($previous.unit; $previous.max)) as $deltaMiB
                | (percent_regression($previous.max; $current.max)) as $regressionPercent
                | if ($regressionPercent > 10) or ($deltaMiB != null and $deltaMiB > 20) then
                    {
                        test: $current.test,
                        metric: $current.metric,
                        statistic: "max",
                        baseline: $previous.max,
                        candidate: $current.max,
                        regressionPercent: $regressionPercent,
                        deltaMiB: $deltaMiB,
                        limit: "10% or 20 MiB"
                    }
                  else empty end
              end
          ] as $violations
        | {
            environmentMatches: (environment($baselineSummary) == environment($candidateSummary)),
            baselineEnvironment: environment($baselineSummary),
            candidateEnvironment: environment($candidateSummary),
            missingMetrics: $missingMetrics,
            unbaselinedMetrics: $unbaselinedMetrics,
            comparedMetrics: ($baseline | length) - ($missingMetrics | length),
            violations: $violations
          }
      '
)

if [[ "$(jq -r '.environmentMatches' <<< "$comparison")" != "true" ]]; then
    print -u2 "UI performance environments are not exactly compatible:"
    jq -r '"baseline=\(.baselineEnvironment | tojson)\ncandidate=\(.candidateEnvironment | tojson)"' \
        <<< "$comparison" >&2
    exit 2
fi

missing_count=$(jq -r '.missingMetrics | length' <<< "$comparison")
unbaselined_count=$(jq -r '.unbaselinedMetrics | length' <<< "$comparison")
if (( missing_count != 0 || unbaselined_count != 0 )); then
    print -u2 "UI performance metric sets do not match the approved baseline:"
    jq -r '
        .missingMetrics[] | "- missing candidate metric: \(.test) — \(.metric), \(.unit)"
      ' <<< "$comparison" >&2
    jq -r '
        .unbaselinedMetrics[] | "- unbaselined candidate metric: \(.test) — \(.metric), \(.unit)"
      ' <<< "$comparison" >&2
    exit 2
fi

violation_count=$(jq -r '.violations | length' <<< "$comparison")
if (( violation_count == 0 )); then
    print "UI performance regression gate passed ($(jq -r '.comparedMetrics' <<< "$comparison") metrics compared)."
    exit 0
fi

print -u2 "UI performance regression gate failed with $violation_count violation(s):"
jq -r '
    .violations[]
    | if .statistic == "max" then
        "- \(.test) — \(.metric) max: \(.baseline) -> \(.candidate) (\(.regressionPercent * 10 | round / 10)% / \(.deltaMiB * 100 | round / 100) MiB; limit \(.limit))"
      else
        "- \(.test) — \(.metric) \(.statistic): \(.baseline) -> \(.candidate) (\(.regressionPercent * 10 | round / 10)%; limit \(.limit))"
      end
  ' <<< "$comparison" >&2
exit 1
