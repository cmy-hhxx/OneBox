#!/bin/zsh

# Builds the complete local app without fetching or updating media tools.
set -euo pipefail

script_directory=${0:A:h}
repository_root=${script_directory:h}
derived_data="$repository_root/.build/DerivedData"
distribution_root="$repository_root/dist"
published_app="$distribution_root/OneBox.app"

if (( $# != 0 )); then
    print -u2 "usage: $0"
    exit 64
fi

if [[ "$(uname -m)" != "arm64" ]]; then
    print -u2 "Apple Silicon (arm64) is required to build OneBox."
    exit 1
fi

if [[ ! -d "$repository_root/Tools/cache" ]]; then
    print -u2 "Missing media-tool cache. Run ./scripts/fetch-podpin-tools.sh first."
    exit 1
fi

if [[ -L "$distribution_root" || -L "$published_app" ]] \
    || [[ -e "$published_app" && ! -d "$published_app" ]]; then
    print -u2 "Release output must be a non-symlink app directory: $published_app"
    exit 1
fi

"$script_directory/bootstrap.sh"
xcodebuild \
    -project "$repository_root/OneBox.xcodeproj" \
    -scheme OneBox \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$derived_data" \
    ARCHS=arm64 \
    ENABLE_CODE_COVERAGE=NO \
    build

mkdir -p "$distribution_root"
staging_directory="$(mktemp -d "$distribution_root/.onebox-release.XXXXXX")"
staged_app="$staging_directory/OneBox.app"
previous_app="$staging_directory/Previous.app"

cleanup() {
    local exit_status=$?
    # If publication fails after moving the previous app, restore it before
    # removing temporary files. Leave the backup intact if restoration fails.
    if [[ -d "$previous_app" && ! -e "$published_app" ]]; then
        if ! mv "$previous_app" "$published_app"; then
            print -u2 "Previous release preserved at: $previous_app"
            return "$exit_status"
        fi
    fi
    rm -rf "$staging_directory"
    return "$exit_status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

ditto "$derived_data/Build/Products/Release/OneBox.app" "$staged_app"
"$script_directory/package-podpin-tools.sh" "$staged_app"

# Only a fully packaged, launch-verified and signed app replaces the deliverable.
# DerivedData remains an intermediate product and may be rebuilt independently.
if [[ -d "$published_app" ]]; then
    mv "$published_app" "$previous_app"
fi
mv "$staged_app" "$published_app"
print "Complete local Release app: $published_app"
