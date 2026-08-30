# Fixture resources

`podpin-sample.m4a` is a generated, eight-second 523.25 Hz sine wave used by
debug builds and playback tests. It contains no public-platform media. SwiftPM
copies it only into the test bundle, where test support resolves it through
`Bundle.module`. `project.yml` separately copies the same package-owned file into
the Debug App resource root and excludes it from Release; only the App adapter
may discover that copy through `Bundle.main`.

Fetch the checksum-locked tools first, then regenerate the fixture from the
repository root:

```sh
./scripts/fetch-podpin-tools.sh
./scripts/generate-podpin-fixture.sh
```

The generation script validates the locked prepared FFmpeg SHA-256, renders the
fixture twice, requires byte-for-byte equality, and checks the output before it
replaces the fixture. The checked-in `podpin-sample.m4a` SHA-256 is
`322960221436fc0b7c3c8d6076b2afcb3ebcded91b34652f814389263ca8fe06`.

Fixture-only metadata and generated short audio used by debug builds and tests
belong here. Do not put real public-platform media in this directory.
