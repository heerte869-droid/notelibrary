# Image utility provenance

cwebp is libwebp 1.6.0. NoteLibrary combines the official macOS arm64 and x86-64 executables into a universal binary for lossless PNG-to-WebP transport.

- [Official downloads](https://developers.google.com/speed/webp/download)
- [Upstream source](https://chromium.googlesource.com/webm/libwebp)
- [COPYING](libwebp-COPYING) and [PATENTS](libwebp-PATENTS)
- [Archive, binary and architecture-slice hashes](libwebp-provenance.json)

## Embedded libraries

Full notices are in ../Licenses. The official prebuilt archive does not supply a complete dependency build manifest; a license source tag is not automatically a verified binary version.

| Component | Evidence in the executable | License text source |
| --- | --- | --- |
| libpng | Explicit libpng version 1.6.47 | Official v1.6.47 |
| libjpeg-turbo | Explicit version 3.1.0, build 20241215 | Official 3.1.0 license and IJG README |
| zlib | Explicit deflate/inflate 1.3.1 copyright strings | Official v1.3.1 |
| LibTIFF | TIFF decoder/codec diagnostics; precise version not established | Official v4.7.0 license, retained as an attribution source, not a binary-version assertion |
| Zstandard | ZSTD codec diagnostics and 1.5.6 string; no upstream build manifest | Official v1.5.6 BSD license |
| liblzma | LZMA codec diagnostics and 5.8.1 string; no upstream build manifest | Official XZ v5.8.1 licensing summary and 0BSD text |

This software is based in part on the work of the Independent JPEG Group.

Only liblzma is embedded; XZ command-line programs and scripts are not included. Zstandard's BSD license is used here. These attributions do not imply endorsement.

## Updating

Obtain both architecture archives from the official site; record exact URLs and hashes. Verify each thin executable before combining them with lipo. Review static dependencies and notices on every update, then run image-pipeline tests. A new binary can introduce additional dependencies.

For Developer ID releases, sign this nested executable before the enclosing application; notarize and validate the release package. A source rebuild should record compiler, deployment target, dependency revisions, build options and notices. This prebuilt utility is traceable to upstream archives; a bit-for-bit source rebuild has not been established.
