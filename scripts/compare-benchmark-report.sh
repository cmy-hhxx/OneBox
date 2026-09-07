#!/bin/zsh

set -euo pipefail

if (( $# != 2 )); then
    print -u2 "usage: $0 <baseline-report> <candidate-report>"
    exit 64
fi

baseline_path=$1
candidate_path=$2

validate_report() {
    local report_path=$1

    if [[ ! -f "$report_path" ]]; then
        print -u2 "Benchmark report does not exist: $report_path"
        return 2
    fi

    if ! jq -e '
        def is_peak_physical_memory:
            .metric | startswith("Memory Peak Physical");
        def has_supported_memory_unit:
            (.metric | endswith(", kB"))
            or (.metric | endswith(", KB"))
            or (.metric | endswith(", bytes"))
            or (.metric | endswith(", B"))
            or (.metric | endswith(", MiB"))
            or (.metric | endswith(", MB"));
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
        and (.measurements | type == "array" and length > 0)
        and any(.measurements[]; .metric == "Clock Monotonic Time, s")
        and all(.measurements[];
            (.test | type == "string" and length > 0)
            and (.metric | type == "string" and length > 0)
            and (.average | type == "number")
            and (.median | type == "number")
            and (.p95 | type == "number")
            and (.max | type == "number")
            and (.samples | type == "array" and length >= 30)
            and all(.samples[]; type == "number")
            and ((is_peak_physical_memory | not) or has_supported_memory_unit)
        )
        and (
            ([.measurements[] | [.test, .metric] | @json] | length)
            == ([.measurements[] | [.test, .metric] | @json] | unique | length)
        )
      ' "$report_path" >/dev/null; then
        print -u2 "Invalid benchmark report (expected a positive display refresh rate plus nonempty, unique 30-sample series including a clock metric): $report_path"
        return 2
    fi
}

validate_report "$baseline_path" || exit 2
validate_report "$candidate_path" || exit 2

comparison=$(
    jq -n \
        --slurpfile baseline "$baseline_path" \
        --slurpfile candidate "$candidate_path" '
        def measurement_key:
            [.test, .metric] | @json;
        def is_relevant:
            .metric == "Clock Monotonic Time, s"
            or (.metric | startswith("Memory Peak Physical"));
        def percent_regression($before; $after):
            if $before > 0 then (($after - $before) / $before * 100) else null end;
        def memory_mib($metric; $value):
            if $metric | endswith(", kB") then $value / 1024
            elif $metric | endswith(", KB") then $value / 1024
            elif $metric | endswith(", bytes") then $value / 1048576
            elif $metric | endswith(", B") then $value / 1048576
            elif $metric | endswith(", MiB") then $value
            elif $metric | endswith(", MB") then $value
            else null
            end;

        $baseline[0] as $baseline_report
        | $candidate[0] as $candidate_report
        | ["architecture", "cpu", "memoryBytes", "macOS", "Xcode", "displayRefreshRate"] as $environment_fields
        | [
            $environment_fields[] as $field
            | select($baseline_report.environment[$field] != $candidate_report.environment[$field])
            | {
                field: $field,
                baseline: $baseline_report.environment[$field],
                candidate: $candidate_report.environment[$field]
              }
          ] as $environment_mismatches
        | (
            $baseline_report.measurements
            | map(select(is_relevant) | {key: measurement_key, value: .})
            | from_entries
          ) as $baseline_by_key
        | (
            $candidate_report.measurements
            | map(select(is_relevant) | {key: measurement_key, value: .})
            | from_entries
          ) as $candidate_by_key
        | [
            $baseline_report.measurements[]
            | select(is_relevant)
            | (measurement_key) as $key
            | select($candidate_by_key[$key] == null)
            | {test, metric}
          ] as $missing_measurements
        | [
            $candidate_report.measurements[]
            | select(is_relevant)
            | (measurement_key) as $key
            | select($baseline_by_key[$key] == null)
            | {test, metric}
          ] as $unbaselined_measurements
        | [
            $baseline_report.measurements[]
            | select(is_relevant)
            | . as $previous
            | (measurement_key) as $key
            | $candidate_by_key[$key] as $current
            | select($current != null)
            | if $current.metric == "Clock Monotonic Time, s" then
                (
                    if ($previous.median > 0 and ($current.median / $previous.median) > 1.10) then
                        {
                            test: $current.test,
                            metric: $current.metric,
                            statistic: "median",
                            baseline: $previous.median,
                            candidate: $current.median,
                            regressionPercent: percent_regression($previous.median; $current.median),
                            limit: "10%"
                        }
                    else empty
                    end
                ),
                (
                    if ($previous.p95 > 0 and ($current.p95 / $previous.p95) > 1.15) then
                        {
                            test: $current.test,
                            metric: $current.metric,
                            statistic: "p95",
                            baseline: $previous.p95,
                            candidate: $current.p95,
                            regressionPercent: percent_regression($previous.p95; $current.p95),
                            limit: "15%"
                        }
                    else empty
                    end
                )
            else
                (memory_mib($current.metric; $current.max) - memory_mib($previous.metric; $previous.max)) as $delta_mib
                | (percent_regression($previous.max; $current.max)) as $regression_percent
                | if (($regression_percent != null and $regression_percent > 10) or $delta_mib > 20) then
                    {
                        test: $current.test,
                        metric: $current.metric,
                        statistic: "max",
                        baseline: $previous.max,
                        candidate: $current.max,
                        regressionPercent: $regression_percent,
                        deltaMiB: $delta_mib,
                        limit: "10% or 20 MiB"
                    }
                else empty
                end
            end
          ] as $violations
        | {
            baselineBenchmark: $baseline_report.benchmark,
            candidateBenchmark: $candidate_report.benchmark,
            environmentMismatches: $environment_mismatches,
            missingMeasurements: $missing_measurements,
            unbaselinedMeasurements: $unbaselined_measurements,
            comparedMeasurements: (
                [$baseline_report.measurements[] | select(is_relevant)] | length
              ) - ($missing_measurements | length),
            violations: $violations
          }
    '
)

if [[ "$(jq -r '.baselineBenchmark == .candidateBenchmark' <<< "$comparison")" != "true" ]]; then
    print -u2 "Benchmark names do not match: $(jq -r '.baselineBenchmark' <<< "$comparison") vs $(jq -r '.candidateBenchmark' <<< "$comparison")"
    exit 2
fi

environment_mismatch_count=$(jq -r '.environmentMismatches | length' <<< "$comparison")
if (( environment_mismatch_count != 0 )); then
    print -u2 "Benchmark environments are not exactly compatible:"
    jq -r '
        .environmentMismatches[]
        | "- \(.field): baseline=\(.baseline | tojson), candidate=\(.candidate | tojson)"
      ' <<< "$comparison" >&2
    exit 2
fi

missing_measurement_count=$(jq -r '.missingMeasurements | length' <<< "$comparison")
if (( missing_measurement_count != 0 )); then
    print -u2 "Candidate report is missing relevant baseline measurements:"
    jq -r '
        .missingMeasurements[]
        | "- \(.test) — \(.metric)"
      ' <<< "$comparison" >&2
    exit 2
fi

unbaselined_measurement_count=$(jq -r '.unbaselinedMeasurements | length' <<< "$comparison")
if (( unbaselined_measurement_count != 0 )); then
    print -u2 "Candidate report contains relevant measurements absent from the approved baseline:"
    jq -r '
        .unbaselinedMeasurements[]
        | "- \(.test) — \(.metric)"
      ' <<< "$comparison" >&2
    exit 2
fi

compared_measurements=$(jq -r '.comparedMeasurements' <<< "$comparison")
if (( compared_measurements == 0 )); then
    print -u2 "No comparable clock or peak physical-memory measurements were found."
    exit 2
fi

violation_count=$(jq -r '.violations | length' <<< "$comparison")
if (( violation_count == 0 )); then
    print "Benchmark regression gate passed ($compared_measurements measurements compared)."
    exit 0
fi

print -u2 "Benchmark regression gate failed with $violation_count violation(s):"
jq -r '
    .violations[]
    | if .statistic == "max" then
        "- \(.test) — \(.metric) \(.statistic): \(.baseline) -> \(.candidate) (\((.regressionPercent // 0) * 10 | round / 10)% / \(.deltaMiB * 100 | round / 100) MiB; limit \(.limit))"
      else
        "- \(.test) — \(.metric) \(.statistic): \(.baseline) -> \(.candidate) (\(.regressionPercent * 10 | round / 10)%; limit \(.limit))"
      end
' <<< "$comparison" >&2
exit 1
