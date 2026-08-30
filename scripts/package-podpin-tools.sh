#!/usr/bin/env bash

# Copies only already-verified cache contents into a built OneBox.app.
# Deliberately does not download anything: run fetch-podpin-tools.sh beforehand.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'usage: %s /path/to/OneBox.app\n' "$0" >&2
  exit 64
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

for command in jq shasum file lipo ditto chmod mkdir rm rg awk otool tail tr codesign install_name_tool plutil mktemp; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "$command" >&2
    exit 1
  fi
done

verify_no_entitlements() {
  local code_path="$1"
  local entitlements_dump
  entitlements_dump="$(mktemp /tmp/onebox-app-entitlements.XXXXXX)"
  if ! codesign --display --entitlements "$entitlements_dump" --xml "$code_path" \
      >/dev/null 2>&1
  then
    rm -f "$entitlements_dump"
    printf 'unable to inspect app entitlements: %s\n' "$code_path" >&2
    exit 1
  fi
  if [[ -s "$entitlements_dump" ]] \
      && ! plutil -convert json -o - "$entitlements_dump" | jq -e 'length == 0' >/dev/null
  then
    rm -f "$entitlements_dump"
    printf 'Release app must not contain code-signing entitlements: %s\n' "$code_path" >&2
    exit 1
  fi
  rm -f "$entitlements_dump"
}

app_path="$1"
lock_file="$repo_root/Tools/tool-lock.json"
yt_dlp_entitlements="$repo_root/Tools/yt-dlp.entitlements.plist"

[[ -d "$app_path" && ! -L "$app_path" ]] || {
  printf 'app must be an existing non-symlink directory: %s\n' "$app_path" >&2
  exit 1
}
[[ "$app_path" == *.app && -f "$app_path/Contents/Info.plist" ]] || {
  printf 'expected a OneBox.app bundle: %s\n' "$app_path" >&2
  exit 1
}
[[ ! -f "$app_path/Contents/MacOS/OneBox.debug.dylib" ]] || {
  printf 'Debug app bundles cannot be packaged with an ad-hoc Hardened Runtime signature; build OneBox in Release configuration\n' >&2
  exit 1
}
app_executable="$app_path/Contents/MacOS/OneBox"
[[ -f "$app_executable" && "$(lipo -archs "$app_executable")" == "arm64" ]] || {
  printf 'OneBox app must be an arm64-only executable: %s\n' "$app_executable" >&2
  exit 1
}
if otool -l "$app_executable" \
    | rg -q 'segname __LLVM_COV|sectname __llvm_(covmap|prf_)'
then
  printf 'Release app must not contain LLVM coverage instrumentation: %s\n' "$app_executable" >&2
  exit 1
fi
verify_no_entitlements "$app_path"
[[ -f "$lock_file" ]] || { printf 'missing tool lock: %s\n' "$lock_file" >&2; exit 1; }
[[ -f "$yt_dlp_entitlements" ]] || {
  printf 'missing yt-dlp signing entitlements: %s\n' "$yt_dlp_entitlements" >&2
  exit 1
}
plutil -convert json -o - "$yt_dlp_entitlements" \
  | jq -e '
      keys == ["com.apple.security.cs.disable-library-validation"]
      and ."com.apple.security.cs.disable-library-validation" == true
    ' >/dev/null || {
  printf 'yt-dlp signing entitlements must contain only com.apple.security.cs.disable-library-validation=true\n' >&2
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
package_subdirectory="$(jq -r '.packageSubdirectory' "$lock_file")"
notices_package_subdirectory="$(jq -r '.noticesPackageSubdirectory' "$lock_file")"
[[ "$cache_directory" == "Tools/cache" ]] || {
  printf 'unexpected tool cache directory in lock: %s\n' "$cache_directory" >&2
  exit 1
}
[[ "$package_subdirectory" == "Contents/Resources/Tools" ]] || {
  printf 'unexpected tool destination in lock: %s\n' "$package_subdirectory" >&2
  exit 1
}
[[ "$notices_package_subdirectory" == "Contents/Resources/ThirdPartyNotices/Tools" ]] || {
  printf 'unexpected notice destination in lock: %s\n' "$notices_package_subdirectory" >&2
  exit 1
}
cache_root="$repo_root/$cache_directory"
tool_destination="$app_path/$package_subdirectory"
notice_destination="$app_path/$notices_package_subdirectory"
notice_root="$(dirname "$notice_destination")"
grdb_notice_destination="$notice_root/GRDB"
grdb_license="$repo_root/Licenses/GRDB-MIT.txt"

validate_sha256() {
  local expected="$1"
  local path="$2"
  local actual
  actual="$(shasum -a 256 "$path" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || {
    printf 'SHA-256 mismatch for cached artifact %s\n' "$path" >&2
    exit 1
  }
}

validate_relative_path() {
  local path="$1"
  [[ -n "$path" && "$path" != /* && "$path" != */ && "$path" != *//* ]] || {
    printf 'invalid relative path in tool lock: %s\n' "$path" >&2
    exit 1
  }

  local component
  while IFS= read -r component; do
    [[ -n "$component" && "$component" != "." && "$component" != ".." ]] || {
      printf 'invalid relative path in tool lock: %s\n' "$path" >&2
      exit 1
    }
  done < <(printf '%s\n' "$path" | awk -F/ '{ for (i = 1; i <= NF; i++) print $i }')
}

validate_cache_path() {
  local path="$1"
  validate_relative_path "$path"

  local component current="$cache_root"
  [[ ! -L "$current" ]] || {
    printf 'tool cache path must not contain a symlink: %s\n' "$current" >&2
    exit 1
  }
  while IFS= read -r component; do
    current="$current/$component"
    [[ ! -L "$current" ]] || {
      printf 'tool cache path must not contain a symlink: %s\n' "$current" >&2
      exit 1
    }
  done < <(printf '%s\n' "$path" | awk -F/ '{ for (i = 1; i <= NF; i++) print $i }')
}

validate_arm64_mach_o() {
  local path="$1"
  file -b "$path" | rg -q 'Mach-O' || {
    printf 'not a Mach-O executable: %s\n' "$path" >&2
    exit 1
  }
  local architectures
  architectures="$(lipo -archs "$path")"
  [[ "$architectures" == "arm64" ]] || {
    printf 'not arm64-only: %s (%s)\n' "$path" "$architectures" >&2
    exit 1
  }
}

rm -rf "$tool_destination" "$notice_destination" "$grdb_notice_destination"
mkdir -p "$tool_destination" "$notice_destination" "$grdb_notice_destination"
[[ -f "$grdb_license" ]] || {
  printf 'missing repository GRDB license: %s\n' "$grdb_license" >&2
  exit 1
}
ditto "$grdb_license" "$grdb_notice_destination/LICENSE"

while IFS=$'\x1f' read -r name source_build sha256 cache_file prepared_cache_file prepared_sha256 package_file thin_to_arm64 source_artifact_id; do
  validate_cache_path "$prepared_cache_file"
  [[ "$package_file" != */* && "$package_file" != .* && -n "$package_file" ]] || {
    printf 'invalid package filename in tool lock: %s\n' "$package_file" >&2
    exit 1
  }
  prepared="$cache_root/$prepared_cache_file"
  destination="$tool_destination/$package_file"
  candidate="$prepared"
  temporary=""
  if [[ "$source_build" == "true" ]]; then
    local_source_record="$(jq -r --arg id "$source_artifact_id" '
      .provenanceArtifacts[] | select(.id == $id) | [.sha256, .cacheFile] | @tsv
    ' "$lock_file")"
    [[ -n "$local_source_record" ]] || {
      printf 'missing source provenance for %s\n' "$name" >&2
      exit 1
    }
    IFS=$'\t' read -r source_sha256 source_cache_file <<< "$local_source_record"
    validate_cache_path "$source_cache_file"
    [[ -f "$cache_root/$source_cache_file" ]] || {
      printf 'missing source cache for %s; run scripts/fetch-podpin-tools.sh first\n' "$name" >&2
      exit 1
    }
    validate_sha256 "$source_sha256" "$cache_root/$source_cache_file"
    [[ -f "$prepared" ]] || {
      printf 'missing source-built cache for %s; run scripts/fetch-podpin-tools.sh first\n' "$name" >&2
      exit 1
    }
  else
    validate_cache_path "$cache_file"
    source="$cache_root/$cache_file"
    [[ -f "$source" ]] || {
      printf 'missing verified cache for %s; run scripts/fetch-podpin-tools.sh first\n' "$name" >&2
      exit 1
    }
    validate_sha256 "$sha256" "$source"
    if [[ "$thin_to_arm64" == "true" ]]; then
      temporary="$tool_destination/.${package_file}.arm64-$$"
      rm -f "$temporary"
      lipo "$source" -thin arm64 -output "$temporary"
      chmod 755 "$temporary"
      candidate="$temporary"
    elif [[ ! -f "$prepared" ]]; then
      printf 'missing prepared cache for %s; run scripts/fetch-podpin-tools.sh first\n' "$name" >&2
      exit 1
    fi
  fi
  if [[ ! -f "$candidate" ]]; then
    printf 'missing prepared cache for %s; run scripts/fetch-podpin-tools.sh first\n' "$name" >&2
    exit 1
  fi
  validate_sha256 "$prepared_sha256" "$candidate"
  validate_arm64_mach_o "$candidate"
  ditto "$candidate" "$destination"
  chmod 755 "$destination"
  validate_sha256 "$prepared_sha256" "$destination"
  validate_arm64_mach_o "$destination"
  [[ -z "$temporary" ]] || rm -f "$temporary"
done < <(
  jq -r '.tools[] | [
    .name,
    ((.sourceBuild // false) | tostring),
    (.sha256 // ""),
    (.cacheFile // ""),
    .preparedCacheFile,
    .preparedSha256,
    .packageFile,
    ((.thinToArm64 // false) | tostring),
    .sourceArtifactID
  ] | join("\u001f")' "$lock_file"
)

while IFS=$'\t' read -r id sha256 cache_file package_relative_path; do
  [[ "$package_relative_path" != "" && "$package_relative_path" != "null" ]] || continue
  [[ "$cache_file" != /* && "$cache_file" != *".."* && "$package_relative_path" != /* && "$package_relative_path" != *".."* ]] || {
    printf 'invalid provenance path in tool lock for %s\n' "$id" >&2
    exit 1
  }
  source="$cache_root/$cache_file"
  destination="$notice_destination/$package_relative_path"
  [[ -f "$source" ]] || {
    printf 'missing verified provenance artifact %s; run scripts/fetch-podpin-tools.sh first\n' "$id" >&2
    exit 1
  }
  validate_sha256 "$sha256" "$source"
  mkdir -p "$(dirname "$destination")"
  ditto "$source" "$destination"
done < <(
  jq -r '.provenanceArtifacts[] | [.id, .sha256, .cacheFile, .packageRelativePath] | @tsv' "$lock_file"
)

printf '%s\n' "$(jq -r '.distributionCaveat' "$lock_file")" > "$notice_destination/DISTRIBUTION_CAVEAT.txt"

# Give recipients the exact FFmpeg source URL, digest, toolchain, and configure
# command that produced the cached binaries. The source archive is also copied
# above because it has a packageRelativePath in the lock.
while IFS=$'\t' read -r build_id source_artifact_id notice_relative_path; do
  [[ -n "$build_id" ]] || continue
  validate_relative_path "$notice_relative_path"
  source_record="$(jq -r --arg id "$source_artifact_id" '
    .provenanceArtifacts[] | select(.id == $id) | [.url, .sha256] | @tsv
  ' "$lock_file")"
  [[ -n "$source_record" ]] || {
    printf 'missing source provenance for build %s\n' "$build_id" >&2
    exit 1
  }
  IFS=$'\t' read -r source_url source_sha256 <<< "$source_record"
  source_notice="$notice_destination/$notice_relative_path"
  mkdir -p "$(dirname "$source_notice")"
  {
    printf 'PodPin source-build provenance\n\n'
    printf 'Build ID: %s\n' "$build_id"
    printf 'Source URL: %s\n' "$source_url"
    printf 'Source SHA-256: %s\n' "$source_sha256"
    printf 'Locked toolchain:\n'
    jq -r --arg id "$build_id" '
      .sourceBuilds[] | select(.id == $id) | .toolchain
      | to_entries[] | "  \(.key): \(.value)"
    ' "$lock_file"
    printf 'Configure arguments:\n'
    jq -r --arg id "$build_id" '.sourceBuilds[] | select(.id == $id) | .configureArguments[] | "  " + .' "$lock_file"
  } > "$source_notice"
done < <(
  jq -r '.sourceBuilds[] | [.id, .sourceArtifactID, .noticeRelativePath] | @tsv' "$lock_file"
)

verify_tool_launch() {
  local name="$1"
  local expected_version="$2"
  local executable="$tool_destination/$name"
  local version_line
  if [[ "$name" == "yt-dlp" ]]; then
    version_line="$("$executable" --version 2>/dev/null || true)"
    [[ "$version_line" == "$expected_version" ]] || {
      printf 'bundled %s version mismatch\nexpected: %s\nactual:   %s\n' \
        "$name" "$expected_version" "$version_line" >&2
      exit 1
    }
  else
    version_line="$("$executable" -version 2>/dev/null | awk 'NR == 1' || true)"
    [[ "$version_line" == "$name version $expected_version"* ]] || {
      printf 'bundled %s version mismatch\nexpected prefix: %s\nactual:          %s\n' \
        "$name" "$name version $expected_version" "$version_line" >&2
      exit 1
    }
  fi
}

while IFS=$'\t' read -r name version; do
  verify_tool_launch "$name" "$version"
done < <(jq -r '.tools[] | [.packageFile, .version] | @tsv' "$lock_file")

# FFMPEG_CONFIGURATION is required for FFmpeg compliance screening. This does
# not replace a licensing review of the selected static build.
for executable in "$tool_destination/ffmpeg" "$tool_destination/ffprobe"; do
  configuration="$($executable -hide_banner -buildconf 2>/dev/null || true)"
  if [[ -z "$configuration" ]]; then
    printf 'unable to inspect FFmpeg build configuration: %s\n' "$executable" >&2
    exit 1
  fi
  if printf '%s\n' "$configuration" | rg -q -- '--enable-gpl|--enable-version3|--enable-nonfree'; then
    printf 'FFmpeg build has a disallowed license configuration: %s\n' "$executable" >&2
    exit 1
  fi
  normalized_configuration="$(printf '%s\n' "$configuration" | tr -d "'")"
  while IFS= read -r required_argument; do
    printf '%s\n' "$normalized_configuration" | rg -F -q -- "$required_argument" || {
      printf 'FFmpeg build is missing locked configure argument %s: %s\n' \
        "$required_argument" "$executable" >&2
      exit 1
    }
  done < <(jq -r '.sourceBuilds[] | .configureArguments[]' "$lock_file")
done

# Every bundled executable must resolve only system-supplied dynamic libraries.
# This includes the PyInstaller-based yt-dlp executable, not only FFmpeg.
while IFS= read -r tool_name; do
  executable="$tool_destination/$tool_name"
  if otool -L "$executable" | tail -n +2 | awk '{print $1}' | rg -qv '^/System/Library/|^/usr/lib/'; then
    printf 'tool has a non-system dynamic dependency: %s\n' "$executable" >&2
    exit 1
  fi
done < <(jq -r '.tools[].packageFile' "$lock_file")

remove_nonrelocatable_package_rpaths() {
  local binary="$1"
  [[ -f "$binary" ]] || return 0

  while IFS= read -r rpath; do
    [[ "$rpath" == /*/PackageFrameworks ]] || continue
    install_name_tool -delete_rpath "$rpath" "$binary"
  done < <(otool -l "$binary" | awk '$1 == "path" { print $2 }')
}

remove_nonrelocatable_package_rpaths "$app_executable"

verify_runtime_signature() {
  local path="$1"
  local signature_details
  codesign --verify --strict --verbose=2 "$path"
  signature_details="$(codesign --display --verbose=4 "$path" 2>&1)" || {
    printf 'unable to inspect code signature: %s\n' "$path" >&2
    exit 1
  }
  printf '%s\n' "$signature_details" | rg -q 'flags=.*\([^)]*runtime[^)]*\)' || {
    printf 'code signature is missing the hardened runtime flag: %s\n' "$path" >&2
    exit 1
  }
}

verify_exact_yt_dlp_entitlements() {
  local executable="$1"
  local entitlements_dump
  entitlements_dump="$(mktemp /tmp/onebox-ytdlp-entitlements.XXXXXX)"
  local is_valid=false
  if codesign --display --entitlements "$entitlements_dump" --xml "$executable" \
      >/dev/null 2>&1 \
    && plutil -convert json -o - "$entitlements_dump" \
      | jq -e '
          keys == ["com.apple.security.cs.disable-library-validation"]
          and ."com.apple.security.cs.disable-library-validation" == true
        ' >/dev/null
  then
    is_valid=true
  fi
  rm -f "$entitlements_dump"
  [[ "$is_valid" == "true" ]] || {
    printf 'signed yt-dlp has unexpected entitlements: %s\n' "$executable" >&2
    exit 1
  }
}

while IFS= read -r tool_name; do
  executable="$tool_destination/$tool_name"
  if [[ "$tool_name" == "yt-dlp" ]]; then
    codesign --force --sign - --timestamp=none --options runtime \
      --entitlements "$yt_dlp_entitlements" "$executable"
  else
    codesign --force --sign - --timestamp=none --options runtime "$executable"
  fi
done < <(jq -r '.tools[].packageFile' "$lock_file")

# Re-sign the outer bundle after its nested executables. The Release app is
# required to carry no entitlements; deep signing also repairs nested code.
codesign --force --deep --sign - --timestamp=none --options runtime "$app_path"
if otool -l "$app_executable" | awk '$1 == "path" && $2 ~ /^\// && $2 ~ /\/PackageFrameworks$/ { found = 1 } END { exit !found }'; then
  printf 'app binary retains a non-relocatable package rpath: %s\n' "$app_executable" >&2
  exit 1
fi
while IFS=$'\t' read -r tool_name version; do
  verify_runtime_signature "$tool_destination/$tool_name"
  verify_tool_launch "$tool_name" "$version"
  if [[ "$tool_name" == "yt-dlp" ]]; then
    verify_exact_yt_dlp_entitlements "$tool_destination/$tool_name"
  fi
done < <(jq -r '.tools[] | [.packageFile, .version] | @tsv' "$lock_file")
verify_runtime_signature "$app_path"
verify_no_entitlements "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"

printf 'Packaged and signed verified PodPin tools into %s\n' "$tool_destination"
