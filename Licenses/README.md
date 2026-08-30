# License material

`GRDB-MIT.txt` is copied by every ordinary build as
`Contents/Resources/GRDB-MIT.txt`. The optional offline-tool packaging step also
copies it to `Contents/Resources/ThirdPartyNotices/GRDB/LICENSE` beside the
media-tool notices.

Media-tool notices are fetched from their pinned, checksummed upstream URLs and
placed directly in each release app bundle under
`Contents/Resources/ThirdPartyNotices/Tools/`; their provenance lives in
`Tools/tool-lock.json`. Keep a copied notice here only when an application
dependency requires it, and reference it from `THIRD_PARTY_NOTICES.md`.
