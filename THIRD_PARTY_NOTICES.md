# Third-party notices

NoteLibrary's project license does not replace the licenses below. Preserve these notices when redistributing the source or application.

| Component | Source/version | Retained license |
| --- | --- | --- |
| [MacPaw/OpenAI](https://github.com/MacPaw/OpenAI) | `c155b5245243f4984791bbe2db80be509b00854a` | [MIT](Vendor/OpenAI/LICENSE), [local patches](Vendor/OpenAI/UPSTREAM.md) |
| [Swift OpenAPI Runtime](https://github.com/apple/swift-openapi-runtime) | 1.13.0, `50ad7976f18fec6c09466d2aebf7be3dc9476cfb` | [Apache-2.0](Resources/Licenses/swift-openapi-runtime-LICENSE.txt), [NOTICE](Resources/Licenses/swift-openapi-runtime-NOTICE.txt) |
| [Swift HTTP Types](https://github.com/apple/swift-http-types) | 1.8.0, `bff4b6903cdc99dda49649dd52f46c11cfd3ed50` | [Apache-2.0](Resources/Licenses/swift-http-types-LICENSE.txt), [NOTICE](Resources/Licenses/swift-http-types-NOTICE.txt) |
| [LiteLLM](https://github.com/BerriAI/litellm) DashScope image mapping | `d80f8c28ca7e2fba4257b4b97457d3b313ff0d6a` | [MIT](Vendor/ProviderReferences/LiteLLM/LICENSE), [port description](Vendor/ProviderReferences/LiteLLM/UPSTREAM.md) |
| [KaTeX](https://github.com/KaTeX/KaTeX) and fonts | 0.18.9 | [MIT](Resources/KaTeX/LICENSE), [additional font-project notice](Resources/Licenses/KaTeX-fonts-MIT.txt) |
| [Lobe Icons](https://github.com/lobehub/lobe-icons) provider marks | Static SVG 1.95.1 | [MIT](Resources/AI_BRAND_ICONS_LICENSE.txt) |
| [libwebp](https://developers.google.com/speed/webp/) cwebp | 1.6.0 | [BSD-3-Clause](Resources/Tools/libwebp-COPYING), [patent grant](Resources/Tools/libwebp-PATENTS), [binary provenance](Resources/Tools/THIRD_PARTY.md) |

The LiteLLM reference Python file is not executed or bundled. No enterprise source is included. Provider names and marks identify their respective services; they do not imply sponsorship or endorsement.

## Libraries embedded in cwebp

The image utility has static dependencies outside Swift Package Manager:

- libpng: [PNG Reference Library License](Resources/Licenses/libpng-LICENSE.txt).
- libjpeg-turbo / Independent JPEG Group: [license overview and BSD terms](Resources/Licenses/libjpeg-turbo-LICENSE.md), [IJG README and license](Resources/Licenses/libjpeg-turbo-README.ijg).
- zlib: [zlib license](Resources/Licenses/zlib-LICENSE.txt).
- LibTIFF: [LibTIFF license](Resources/Licenses/libtiff-LICENSE.md).
- Zstandard: [BSD license](Resources/Licenses/zstd-LICENSE.txt).
- XZ Utils / liblzma: [licensing scope](Resources/Licenses/xz-COPYING.txt), [0BSD](Resources/Licenses/xz-COPYING.0BSD.txt).

This software is based in part on the work of the Independent JPEG Group.

Only liblzma is embedded; XZ command-line programs and scripts are not included. License URLs and hashes are recorded in [SOURCES.json](Resources/Licenses/SOURCES.json). Version evidence and its limits are recorded with the [utility](Resources/Tools/THIRD_PARTY.md).

The Xcode application target copies Resources/Licenses, Resources/Tools, Resources/KaTeX, and the Lobe Icons notice into the application. Preserve those resources in binary distributions.

## Test-only resources

Three legacy PowerPoint fixtures originate from [Apache POI](https://poi.apache.org/) under Apache-2.0. Their [license](Tests/Fixtures/APACHE-2.0.txt), upstream [NOTICE](Tests/Fixtures/NOTICE), and [verified revision/hashes](Tests/Fixtures/UPSTREAM.json) accompany them. They are copied to the test bundle, not the application.

Apple system frameworks, system fonts, SQLite, and zlib linked from macOS are supplied by the operating system, not copied into this repository. Codex is an optional external installation, not a bundled executable.
