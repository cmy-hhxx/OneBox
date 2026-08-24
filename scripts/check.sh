#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
repository_root=${script_directory:h}

xcrun swift-format lint \
    --configuration "$repository_root/.swift-format" \
    --recursive \
    --parallel \
    --strict \
    "$repository_root/OneBox" \
    "$repository_root/Tests"

"$script_directory/test.sh"
