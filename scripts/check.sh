#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
repository_root=${script_directory:h}

if [[ "$(uname -m)" != "arm64" ]]; then
    print -u2 "Apple Silicon (arm64) is required to run the project checks."
    exit 1
fi

while IFS=: read -r source_path line_number reference; do
    target=$reference
    target=${target#<}
    target=${target%>}
    case "$target" in
        "" | \#* | http://* | https://* | mailto:*) continue ;;
    esac
    relative_path=${target%%#*}
    resolved_path="${source_path:h}/$relative_path"
    if [[ ! -e "$resolved_path" ]]; then
        print -u2 "$source_path:$line_number: broken local Markdown link: $target"
        exit 1
    fi
done < <(
    rg --line-number --only-matching --replace '$1' --glob '*.md' \
        '\[[^]]*\]\(([^)]+)\)' \
        "$repository_root"
)

xcrun swift-format lint \
    --configuration "$repository_root/.swift-format" \
    --recursive \
    --parallel \
    --strict \
    "$repository_root/OneBox" \
    "$repository_root/Tests"

"$script_directory/test.sh"
