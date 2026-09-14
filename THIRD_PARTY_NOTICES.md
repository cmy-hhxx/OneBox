# Third-party notices

## ascii-simulation-art-console

The luminance quantization and glyph-atlas sampling math in `AsciiShaderSource.swift` is adapted from [`ascii-simulation-art-console`](https://github.com/SkentSun/ascii-simulation-art-console).

MIT License

Copyright (c) 2026 By Skent (@SkentSun)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## GRDB.swift

[GRDB.swift](https://github.com/groue/GRDB.swift), exact version 7.11.1, provides
StockWatch and PodPin SQLite access under the MIT License. The repository copy is
`Licenses/GRDB-MIT.txt`; packaged apps include the same text as `GRDB-MIT.txt`
and `ThirdPartyNotices/GRDB/LICENSE`.

MIT License

Copyright (C) 2015-2025 Gwendal Roué

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## MarketSprite and StockPet-derived code

Parts of the StockWatch implementation are derived from the MarketSprite and StockPet codebase under the following license.

MIT License

Copyright (c) 2026 YellowPancake
Copyright (c) 2026 cmy

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Alert sounds

The bundled alert sounds were trimmed and normalized from these [Creative Commons 0](https://creativecommons.org/publicdomain/zero/1.0/) Freesound recordings:

- `bull-moo.wav`: [“Cow - Moan 2 - 96kHz.wav” by JarredGibb](https://freesound.org/s/233146/)
- `bear-growl.wav`: [“Growl” by whirlproductions](https://freesound.org/s/752374/)

Both source pages mark the recordings as Creative Commons 0. The application copies only the short active sound and removes the original head/tail silence.

## PodPin media tools

PodPin offline downloads use checksum-locked `yt-dlp`, `ffmpeg`, and `ffprobe`
only after `scripts/fetch-podpin-tools.sh` verifies their declared sources and
`scripts/package-podpin-tools.sh` verifies, copies, signs, and re-signs the app.
Exact versions, URLs, hashes, source-build configuration, and notice paths are
recorded in the repository file `Tools/tool-lock.json`. Packaged apps carry its
lock-derived sources, licenses, and build provenance under `ThirdPartyNotices/Tools`.

- `yt-dlp` is distributed with its upstream license, third-party notices, and
  matching source archive.
- FFmpeg and FFprobe are built locally from the pinned FFmpeg 6.1.1 source with
  the locked LGPL-only configuration; the package includes LGPL-2.1 text and
  build provenance.

These mechanical checks are not a legal conclusion. A distributor remains
responsible for the obligations of the actual signed build, including applicable
LGPL relinking and source requirements.

## BoardUI

OneBox's current SwiftUI design system adapts the official free [BoardUI](https://www.boardui.com)
component sources, semantic theme and motion. The source reference was installed
through BoardUI's MCP with CLI 0.5.5 and skill 2026.9.11. Its React/Tailwind project
is a development reference; OneBox ships native SwiftUI controls.

Copyright (c) 2026 Mertcan Dundar Esmergul (BoardUI).

The complete [MIT License](Licenses/BoardUI-MIT.txt) is distributed in the application
as `BoardUI-MIT.txt`. Component mappings and native adaptations are documented in
[BoardUI native adaptation](docs/boardui-native.md).

## Inter

OneBox bundles [Inter](https://github.com/rsms/inter) 4.1 variable font as a
`OneBoxDesignSystem` resource. It is registered only within the running process;
Chinese glyphs use the platform font fallback.

Copyright (c) 2016 The Inter Project Authors.

The font is distributed under the [SIL Open Font License 1.1](Licenses/Inter-OFL.txt),
packaged in the application as `Inter-OFL.txt`.

## Earlier Uiverse UI references

Earlier OneBox UI iterations adapted these MIT-licensed components from Uiverse.
Their attribution is retained as design provenance; BoardUI is the current design
source.

- [Codecite: angry-bullfrog-58](https://uiverse.io/Codecite/angry-bullfrog-58) — primary button surface and press feedback.
- [njesenberger: friendly-otter-40](https://uiverse.io/njesenberger/friendly-otter-40) — compact on/off switch treatment.
- [alexruix: slippery-frog-10](https://uiverse.io/alexruix/slippery-frog-10) — inset field and focus treatment.
- [Yaya12085: rude-mouse-79](https://uiverse.io/Yaya12085/rude-mouse-79) — inset white segmented selection.

The authors' copyright notices and MIT permission text are included in
`Licenses/Uiverse-MIT.txt`, distributed in the application as `Uiverse-MIT.txt`.
