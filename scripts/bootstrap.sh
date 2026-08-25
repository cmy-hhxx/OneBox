#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
repository_root=${script_directory:h}
artifact_root="$repository_root/.build"

command -v xcodegen >/dev/null 2>&1 || {
    print -u2 "xcodegen is required. Install the repository-pinned version with: mise trust && mise install"
    exit 1
}

required_xcodegen_version="$(
    rg --only-matching --replace '$1' \
        '^xcodegen = "([^"]+)"$' \
        "$repository_root/.mise.toml"
)"
installed_xcodegen_version="$(
    xcodegen --version | rg --only-matching '[0-9]+\.[0-9]+\.[0-9]+'
)"

if [[ "$installed_xcodegen_version" != "$required_xcodegen_version" ]]; then
    print -u2 "xcodegen $required_xcodegen_version is required; found $installed_xcodegen_version. Run: mise trust && mise install"
    exit 1
fi

mkdir -p \
    "$artifact_root/DerivedData" \
    "$artifact_root/Logs" \
    "$artifact_root/TestResults"

cd "$repository_root"
xcodegen generate
