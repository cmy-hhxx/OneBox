#!/usr/bin/env bash

# Fetches immutable prebuilt tools, legal notices, and source archives declared
# in Tools/tool-lock.json. FFmpeg/FFprobe are built locally from the locked
# official source; this is the only release-tool script allowed to use network.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [[ $# -ne 0 ]]; then
  printf 'usage: %s\n' "$0" >&2
  exit 64
fi

for command in jq curl shasum file lipo chmod mkdir mv rm rg awk cp tar make sysctl uname xcrun xcodebuild dirname otool tail; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "$command" >&2
    exit 1
  fi
done

lock_file="$repo_root/Tools/tool-lock.json"
[[ -f "$lock_file" ]] || {
  printf 'missing tool lock: %s\n' "$lock_file" >&2
  exit 1
}
[[ "$(jq -r '.schemaVersion' "$lock_file")" == "2" ]] || {
  printf 'unsupported Tools/tool-lock.json schema\n' >&2
  exit 1
}

jq -e '
  .tools | length > 0 and all(.[];
    (.version | type) == "string"
    and (.version | length) > 0
    and (.preparedSha256 | type) == "string"
    and (.preparedSha256 | test("^[0-9a-f]{64}$"))
  )
' "$lock_file" >/dev/null || {
  printf 'missing or invalid prepared tool SHA-256 in tool lock\n' >&2
  exit 1
}

cache_directory="$(jq -r '.cacheDirectory' "$lock_file")"
[[ "$cache_directory" == "Tools/cache" ]] || {
  printf 'unexpected tool cache directory in lock: %s\n' "$cache_directory" >&2
  exit 1
}
cache_root="$repo_root/$cache_directory"

validate_relative_cache_path() {
  local path="$1"
  [[ -n "$path" && "$path" != /* && "$path" != */ && "$path" != *//* ]] || {
    printf 'invalid cache path in tool lock: %s\n' "$path" >&2
    exit 1
  }

  local component current="$cache_root"
  [[ ! -L "$current" ]] || {
    printf 'tool cache path must not contain a symlink: %s\n' "$current" >&2
    exit 1
  }
  while IFS= read -r component; do
    [[ -n "$component" && "$component" != "." && "$component" != ".." ]] || {
      printf 'invalid cache path in tool lock: %s\n' "$path" >&2
      exit 1
    }
    current="$current/$component"
    [[ ! -L "$current" ]] || {
      printf 'tool cache path must not contain a symlink: %s\n' "$current" >&2
      exit 1
    }
  done < <(printf '%s\n' "$path" | awk -F/ '{ for (i = 1; i <= NF; i++) print $i }')
}

validate_sha256() {
  local expected="$1"
  local path="$2"
  local actual
  actual="$(shasum -a 256 "$path" | awk '{print $1}')"
  if [[ "$actual" != "$expected" ]]; then
    printf 'SHA-256 mismatch for %s\nexpected: %s\nactual:   %s\n' \
      "$path" "$expected" "$actual" >&2
    return 1
  fi
}

validate_source_toolchain() {
  local build_id="$1"
  local record
  record="$(jq -r --arg id "$build_id" '
    .sourceBuilds[] | select(.id == $id) | .toolchain
    | [
        .xcodeVersion,
        .xcodeBuildVersion,
        .clangVersion,
        .macosSDKVersion,
        .macosSDKBuildVersion,
        .makeVersion
      ] | @tsv
  ' "$lock_file")"
  [[ -n "$record" ]] || {
    printf 'missing locked source toolchain: %s\n' "$build_id" >&2
    exit 1
  }

  local expected_xcode expected_xcode_build expected_clang
  local expected_sdk expected_sdk_build expected_make
  IFS=$'\t' read -r \
    expected_xcode expected_xcode_build expected_clang \
    expected_sdk expected_sdk_build expected_make <<< "$record"

  local actual_xcode actual_xcode_build actual_clang
  local actual_sdk actual_sdk_build actual_make
  actual_xcode="$(xcodebuild -version | awk 'NR == 1 { print $2 }')"
  actual_xcode_build="$(xcodebuild -version | awk 'NR == 2 { print $3 }')"
  actual_clang="$(xcrun --sdk macosx clang --version | awk 'NR == 1')"
  actual_sdk="$(xcrun --sdk macosx --show-sdk-version)"
  actual_sdk_build="$(xcrun --sdk macosx --show-sdk-build-version)"
  actual_make="$(make --version | awk 'NR == 1')"

  local label expected actual
  while IFS=$'\t' read -r label expected actual; do
    if [[ -z "$expected" || "$actual" != "$expected" ]]; then
      printf 'source toolchain mismatch for %s (%s)\nexpected: %s\nactual:   %s\n' \
        "$build_id" "$label" "$expected" "$actual" >&2
      exit 1
    fi
  done < <(
    printf '%s\t%s\t%s\n' \
      'Xcode' "$expected_xcode" "$actual_xcode" \
      'Xcode build' "$expected_xcode_build" "$actual_xcode_build" \
      'clang' "$expected_clang" "$actual_clang" \
      'macOS SDK' "$expected_sdk" "$actual_sdk" \
      'macOS SDK build' "$expected_sdk_build" "$actual_sdk_build" \
      'make' "$expected_make" "$actual_make"
  )
}

download_artifact() {
  local url="$1"
  local sha256="$2"
  local cache_file="$3"
  local destination="$cache_root/$cache_file"
  local temporary="${destination}.partial"

  validate_relative_cache_path "$cache_file"
  mkdir -p "$(dirname "$destination")"
  if [[ -f "$destination" ]]; then
    validate_sha256 "$sha256" "$destination"
    return
  fi

  if [[ -s "$temporary" ]]; then
    curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 --retry 3 --retry-all-errors \
      --continue-at - --output "$temporary" "$url"
  else
    rm -f -- "$temporary"
    curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 --retry 3 --retry-all-errors \
      --output "$temporary" "$url"
  fi
  if ! validate_sha256 "$sha256" "$temporary"; then
    rm -f -- "$temporary"
    exit 1
  fi
  mv "$temporary" "$destination"
}

is_arm64_mach_o() {
  local path="$1"
  file -b "$path" | rg -q 'Mach-O'
  [[ "$(lipo -archs "$path")" == "arm64" ]]
}

prepare_prebuilt_tool() {
  local name="$1"
  local source_cache_file="$2"
  local prepared_cache_file="$3"
  local prepared_sha256="$4"
  local thin_to_arm64="$5"
  local source="$cache_root/$source_cache_file"
  local prepared="$cache_root/$prepared_cache_file"
  local temporary="${prepared}.partial-$$"

  validate_relative_cache_path "$source_cache_file"
  validate_relative_cache_path "$prepared_cache_file"
  mkdir -p "$(dirname "$prepared")"
  rm -f -- "$temporary"
  if [[ "$thin_to_arm64" == "true" ]]; then
    lipo "$source" -thin arm64 -output "$temporary"
  else
    cp "$source" "$temporary"
  fi
  chmod 755 "$temporary"
  is_arm64_mach_o "$temporary" || {
    printf 'prepared %s is not an arm64 Mach-O executable\n' "$name" >&2
    exit 1
  }
  validate_sha256 "$prepared_sha256" "$temporary"
  mv "$temporary" "$prepared"
}

download_provenance_artifact() {
  local artifact_id="$1"
  local record
  record="$(jq -r --arg id "$artifact_id" '
    .provenanceArtifacts[] | select(.id == $id) | [.url, .sha256, .cacheFile] | @tsv
  ' "$lock_file")"
  [[ -n "$record" ]] || {
    printf 'missing provenance artifact in tool lock: %s\n' "$artifact_id" >&2
    exit 1
  }
  local url sha256 cache_file
  IFS=$'\t' read -r url sha256 cache_file <<< "$record"
  download_artifact "$url" "$sha256" "$cache_file"
}

validate_ffmpeg_configuration() {
  local executable="$1"
  local configuration
  configuration="$($executable -hide_banner -buildconf 2>/dev/null || true)"
  [[ -n "$configuration" ]] || {
    printf 'unable to inspect FFmpeg build configuration: %s\n' "$executable" >&2
    exit 1
  }
  if printf '%s\n' "$configuration" | rg -q -- '--enable-gpl|--enable-version3|--enable-nonfree'; then
    printf 'FFmpeg build has a disallowed license configuration: %s\n' "$executable" >&2
    exit 1
  fi
}

validate_prepared_tool() {
  local name="$1"
  local expected_version="$2"
  local executable="$3"
  local version_line

  if [[ "$name" == "yt-dlp" ]]; then
    version_line="$("$executable" --version 2>/dev/null || true)"
    [[ "$version_line" == "$expected_version" ]] || {
      printf 'prepared %s version mismatch\nexpected: %s\nactual:   %s\n' \
        "$name" "$expected_version" "$version_line" >&2
      exit 1
    }
  else
    version_line="$("$executable" -version 2>/dev/null | awk 'NR == 1' || true)"
    [[ "$version_line" == "$name version $expected_version"* ]] || {
      printf 'prepared %s version mismatch\nexpected prefix: %s\nactual:          %s\n' \
        "$name" "$name version $expected_version" "$version_line" >&2
      exit 1
    }
  fi

  if otool -L "$executable" | tail -n +2 | awk '{ print $1 }' \
    | rg -qv '^/System/Library/|^/usr/lib/'; then
    printf 'prepared tool has a non-system dynamic dependency: %s\n' "$executable" >&2
    exit 1
  fi
}

build_source_build() {
  local build_id="$1"
  local record source_artifact_id source_directory architecture
  record="$(jq -r --arg id "$build_id" '
    .sourceBuilds[] | select(.id == $id)
    | [.sourceArtifactID, .sourceDirectory, .architecture] | @tsv
  ' "$lock_file")"
  [[ -n "$record" ]] || {
    printf 'missing source build in tool lock: %s\n' "$build_id" >&2
    exit 1
  }
  IFS=$'\t' read -r source_artifact_id source_directory architecture <<< "$record"
  [[ "$architecture" == "arm64" && "$(uname -m)" == "arm64" ]] || {
    printf 'source build %s requires an arm64 host\n' "$build_id" >&2
    exit 1
  }
  validate_source_toolchain "$build_id"
  validate_relative_cache_path "$source_directory"

  local source_record source_cache_file
  source_record="$(jq -r --arg id "$source_artifact_id" '
    .provenanceArtifacts[] | select(.id == $id) | [.cacheFile, .kind] | @tsv
  ' "$lock_file")"
  [[ -n "$source_record" ]] || {
    printf 'missing source artifact for build: %s\n' "$build_id" >&2
    exit 1
  }
  local source_kind
  IFS=$'\t' read -r source_cache_file source_kind <<< "$source_record"
  [[ "$source_kind" == "source-archive" ]] || {
    printf 'build source is not an archive: %s\n' "$source_artifact_id" >&2
    exit 1
  }
  validate_relative_cache_path "$source_cache_file"
  local archive="$cache_root/$source_cache_file"
  local source_path="$cache_root/$source_directory"
  local source_parent
  source_parent="$(dirname "$source_path")"

  # The archive is already hash-verified. Reject links before extraction so a
  # locked archive cannot introduce a path that escapes later cache operations.
  if tar -tvf "$archive" | awk '$1 ~ /^[lh]/ { found = 1 } END { exit !found }'; then
    printf 'source archive contains a symbolic or hard link: %s\n' "$archive" >&2
    exit 1
  fi

  # Re-extracting removes any stale local source edits before every release-tool build.
  rm -rf -- "$source_path"
  mkdir -p "$source_parent"
  tar -xf "$archive" -C "$source_parent"
  [[ -x "$source_path/configure" ]] || {
    printf 'source archive did not contain expected configure script: %s\n' "$source_directory" >&2
    exit 1
  }

  local configure_arguments=()
  local configure_argument
  while IFS= read -r configure_argument; do
    configure_arguments+=("$configure_argument")
  done < <(jq -r --arg id "$build_id" '
    .sourceBuilds[] | select(.id == $id) | .configureArguments[]
  ' "$lock_file")
  (( ${#configure_arguments[@]} > 0 )) || {
    printf 'source build has no locked configure arguments: %s\n' "$build_id" >&2
    exit 1
  }

  local jobs
  jobs="$(sysctl -n hw.ncpu 2>/dev/null || printf '1')"
  [[ "$jobs" =~ ^[0-9]+$ && "$jobs" -gt 0 ]] || jobs=1
  xcrun --sdk macosx --find clang >/dev/null
  (
    cd "$source_path"
    export MACOSX_DEPLOYMENT_TARGET=15.0
    ./configure "${configure_arguments[@]}"
    make -j "$jobs" ffmpeg ffprobe
  )

  local name build_product prepared_cache_file prepared_sha256
  while IFS=$'\t' read -r name build_product prepared_cache_file prepared_sha256; do
    validate_relative_cache_path "$prepared_cache_file"
    local source_binary="$source_path/$build_product"
    local prepared_binary="$cache_root/$prepared_cache_file"
    local temporary="${prepared_binary}.partial-$$"
    [[ -f "$source_binary" ]] || {
      printf 'source build %s did not produce %s\n' "$build_id" "$build_product" >&2
      exit 1
    }
    mkdir -p "$(dirname "$prepared_binary")"
    rm -f -- "$temporary"
    cp "$source_binary" "$temporary"
    chmod 755 "$temporary"
    is_arm64_mach_o "$temporary" || {
      printf 'source-built %s is not an arm64 Mach-O executable\n' "$name" >&2
      exit 1
    }
    validate_ffmpeg_configuration "$temporary"
    validate_sha256 "$prepared_sha256" "$temporary"
    mv "$temporary" "$prepared_binary"
  done < <(jq -r --arg id "$build_id" '
    .tools[] | select(.sourceBuild == true and .sourceBuildID == $id)
    | [.name, .buildProduct, .preparedCacheFile, .preparedSha256] | @tsv
  ' "$lock_file")
}

# Shipped notices must always be locally hash-verified.
while IFS=$'\t' read -r url sha256 cache_file; do
  download_artifact "$url" "$sha256" "$cache_file"
done < <(
  jq -r '.provenanceArtifacts[] | select(.packageRelativePath != null) | [.url, .sha256, .cacheFile] | @tsv' "$lock_file"
)

# Source-built tools always require their locked source archive. Packaged source
# archives are fetched by the notice loop above and re-verified here.
while IFS= read -r source_artifact_id; do
  [[ -z "$source_artifact_id" ]] || download_provenance_artifact "$source_artifact_id"
done < <(jq -r '.sourceBuilds[].sourceArtifactID' "$lock_file")

while IFS=$'\t' read -r name url sha256 cache_file prepared_cache_file prepared_sha256 thin_to_arm64; do
  download_artifact "$url" "$sha256" "$cache_file"
  prepare_prebuilt_tool "$name" "$cache_file" "$prepared_cache_file" "$prepared_sha256" "$thin_to_arm64"
done < <(
  jq -r '.tools[] | select((.sourceBuild // false) | not)
    | [.name, .url, .sha256, .cacheFile, .preparedCacheFile, .preparedSha256, .thinToArm64] | @tsv' "$lock_file"
)

while IFS= read -r build_id; do
  [[ -z "$build_id" ]] || build_source_build "$build_id"
done < <(jq -r '.sourceBuilds[].id' "$lock_file")

while IFS=$'\t' read -r name version prepared_cache_file; do
  validate_relative_cache_path "$prepared_cache_file"
  validate_prepared_tool "$name" "$version" "$cache_root/$prepared_cache_file"
done < <(jq -r '.tools[] | [.name, .version, .preparedCacheFile] | @tsv' "$lock_file")

printf 'Verified release tool cache at %s\n' "$cache_root"
