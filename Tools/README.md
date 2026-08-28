# Bundled media-tool policy

`tool-lock.json` is the only authority for `yt-dlp`, `ffmpeg`, and `ffprobe`
versions, upstream URLs, source and prepared-output checksums, upstream
source-release references, and shipped notices.

`scripts/fetch-podpin-tools.sh` is the sole networked step. It downloads the
tools, source archives, and shipped notices into the ignored `Tools/cache/`,
verifies every SHA-256, prepares the universal `yt-dlp` binary as arm64-only,
and builds `ffmpeg` and `ffprobe` locally from the checksum-verified official
FFmpeg source with the locked configuration and exact Xcode, clang, SDK, and
`make` versions. A toolchain mismatch stops before compilation. Cache paths
containing symlinks are rejected before any destructive write. Every generated
prepared tool must match its locked `preparedSha256`, exact semantic version,
arm64 architecture, and system-only dynamic dependency policy.
`scripts/package-podpin-tools.sh` does not access the network: it re-verifies the
source cache and every prepared candidate,
regenerates the packaged `yt-dlp` arm64 slice from the hash-validated upstream
artifact, and copies the locked tools, source archives, and notices into an app
bundle. The package step accepts a Release app only. It rejects Xcode's Debug
app because an ad-hoc Hardened Runtime signature cannot validate the separate
`OneBox.debug.dylib` without weakening the app's library-validation policy.

The runtime uses structured `Process` arguments and fixed command allowlists;
it never invokes a shell, accepts a tool URL from content metadata, or runs an
updater. The release pipeline rejects FFmpeg configurations that advertise
GPL, version3, or nonfree flags and rejects non-system dynamic dependencies for
all three tools. Before signing, it removes build-local `PackageFrameworks` rpaths from the app
executables. It then signs every nested executable and the app with Hardened
Runtime enabled. The PyInstaller-based `yt-dlp` receives only the
`com.apple.security.cs.disable-library-validation` entitlement required to load
its signed unpacked Python runtime. The package step preserves existing app
entitlements, matches every tool's reported semantic version to the lock after
final signing, verifies yt-dlp's exact effective entitlement set, and checks the
runtime flag, relocatable rpaths, and the app's deep strict
signature.

FFmpeg and FFprobe are locally built from the pinned official 6.1.1 source
archive; their exact configure arguments and source digest are included in the
app's third-party notices alongside the source archive itself. The mechanical
checks do not determine redistribution compliance. Treat the packaged app as
a local verification artifact until its distributor has independently met all
applicable attribution, source, and LGPL relinking obligations recorded in the
lock and [third-party notices](../THIRD_PARTY_NOTICES.md).
