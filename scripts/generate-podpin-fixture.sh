#!/usr/bin/env bash

# Rebuilds the checked-in playback fixture with the checksum-locked FFmpeg.

set -euo pipefail

if [[ $# -ne 0 ]]; then
  printf 'usage: %s\n' "$0" >&2
  exit 64
fi

for command in jq shasum awk cmp mv rm dirname; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "$command" >&2
    exit 1
  fi
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lock_file="$repo_root/Tools/tool-lock.json"
fixture="$repo_root/Packages/Tools/PodPinTool/Tests/PodPinToolTests/Resources/Fixtures/podpin-sample.m4a"
expected_fixture_sha256="322960221436fc0b7c3c8d6076b2afcb3ebcded91b34652f814389263ca8fe06"

[[ -f "$lock_file" ]] || {
  printf 'missing tool lock: %s\n' "$lock_file" >&2
  exit 1
}

ffmpeg_record="$(jq -r '
  .tools[] | select(.name == "ffmpeg")
  | [.preparedCacheFile, .preparedSha256] | @tsv
' "$lock_file")"
[[ -n "$ffmpeg_record" ]] || {
  printf 'missing locked FFmpeg record\n' >&2
  exit 1
}
IFS=$'\t' read -r ffmpeg_cache_file ffmpeg_sha256 <<< "$ffmpeg_record"
[[ -n "$ffmpeg_cache_file" && "$ffmpeg_cache_file" != /* && "$ffmpeg_cache_file" != *".."* ]] || {
  printf 'invalid FFmpeg cache path in tool lock: %s\n' "$ffmpeg_cache_file" >&2
  exit 1
}
ffmpeg="$repo_root/Tools/cache/$ffmpeg_cache_file"
[[ -x "$ffmpeg" ]] || {
  printf 'missing locked FFmpeg; run scripts/fetch-podpin-tools.sh first\n' >&2
  exit 1
}

actual_ffmpeg_sha256="$(shasum -a 256 "$ffmpeg" | awk '{print $1}')"
[[ "$actual_ffmpeg_sha256" == "$ffmpeg_sha256" ]] || {
  printf 'locked FFmpeg SHA-256 mismatch\nexpected: %s\nactual:   %s\n' \
    "$ffmpeg_sha256" "$actual_ffmpeg_sha256" >&2
  exit 1
}

first="${fixture}.partial-$$-1"
second="${fixture}.partial-$$-2"
trap 'rm -f -- "$first" "$second"' EXIT
rm -f -- "$first" "$second"

generate_fixture() {
  local destination="$1"
  "$ffmpeg" \
    -hide_banner -loglevel error -nostdin -y \
    -filter_complex 'sine=frequency=523.25:sample_rate=44100:duration=8[fixture]' \
    -map '[fixture]' -map_metadata -1 -map_chapters -1 \
    -c:a aac -b:a 96k -ac 1 -ar 44100 -threads:a 1 \
    -fflags +bitexact -flags:a +bitexact \
    -metadata creation_time='1970-01-01T00:00:00Z' \
    -write_prft 0 -use_editlist 1 -movie_timescale 1000 \
    -movflags +faststart -f ipod "$destination"
}

generate_fixture "$first"
generate_fixture "$second"
cmp -s "$first" "$second" || {
  printf 'fixture generation was not byte-for-byte deterministic\n' >&2
  exit 1
}

actual_fixture_sha256="$(shasum -a 256 "$first" | awk '{print $1}')"
[[ "$actual_fixture_sha256" == "$expected_fixture_sha256" ]] || {
  printf 'fixture SHA-256 mismatch\nexpected: %s\nactual:   %s\n' \
    "$expected_fixture_sha256" "$actual_fixture_sha256" >&2
  exit 1
}

mv "$first" "$fixture"
printf 'Generated %s\nSHA-256: %s\n' "$fixture" "$actual_fixture_sha256"
