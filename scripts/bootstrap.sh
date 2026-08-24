#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
repository_root=${script_directory:h}
artifact_root="$repository_root/.build"

command -v xcodegen >/dev/null 2>&1 || {
    print -u2 "xcodegen is required. Install the repository-pinned version with: mise trust && mise install"
    exit 1
}

mkdir -p \
    "$artifact_root/DerivedData" \
    "$artifact_root/Logs" \
    "$artifact_root/TestResults"

cd "$repository_root"
xcodegen generate
