#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
repository_root=${script_directory:h}
scheme_path="$repository_root/OneBox.xcodeproj/xcshareddata/xcschemes/OneBox.xcscheme"

[[ -f "$scheme_path" ]] || {
    print -u2 "Generated OneBox scheme is missing. Run ./scripts/bootstrap.sh first."
    exit 1
}

coverage_enabled="$(
    xmllint --xpath 'string(/Scheme/TestAction/@codeCoverageEnabled)' "$scheme_path"
)"
if [[ "$coverage_enabled" == "YES" ]]; then
    print -u2 "The generated OneBox scheme unexpectedly enables code coverage."
    exit 1
fi

for configuration in Debug Release; do
    coverage_setting="$(
        xcodebuild \
            -project "$repository_root/OneBox.xcodeproj" \
            -target OneBox \
            -configuration "$configuration" \
            -showBuildSettings 2>/dev/null \
            | rg --only-matching --replace '$1' \
                '^[[:space:]]*ENABLE_CODE_COVERAGE = (YES|NO)$'
    )"
    if [[ -z "$coverage_setting" || "$coverage_setting" == *YES* ]]; then
        print -u2 "$configuration App builds must disable ENABLE_CODE_COVERAGE by default."
        exit 1
    fi
done
