# Third-party maintenance

The public inventory is [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md). NoteLibrary's project license applies to its own work; vendored code, provider marks, math fonts, binary utilities and third-party fixtures retain their respective terms.

## Updates and assets

Keep Package.resolved committed; it pins Swift OpenAPI Runtime and Swift HTTP Types. Keep the vendored SDK's license and documented patches, and rerun protocol tests after updates. The LiteLLM image mapping is a Swift port of non-enterprise source; its Python reference is not a runtime dependency.

Review the [image utility inventory](../Resources/Tools/THIRD_PARTY.md) separately from SwiftPM. Its LibTIFF version is not established by the prebuilt archive; do not invent one in an SBOM. Preserve the test-only Apache POI NOTICE and pinned fixture hashes.

Lobe Icons provider marks identify compatibility, not affiliation. Do not use them as NoteLibrary's own identity. KaTeX and its fonts retain their MIT notices. System fonts and SF Symbols are used through macOS APIs, not redistributed as font files.

For new artwork, fonts, templates or snippets, record an upstream URL, version/revision, license and modifications. Documentation screenshots should use synthetic content and a clean demonstration library.

## AI-assisted contributions

AI assistance does not establish a contribution's provenance, correctness or license compatibility. Review changes and copied snippets, inspect dependencies, and run relevant tests. Do not submit credentials, real notes, diagnostic conversations or user-specific exports. GitHub's [responsible-use guidance](https://docs.github.com/en/copilot/responsible-use/agents) describes public-code matches and the need to review generated changes.

## Builds and distribution

The Xcode project uses relative paths and a shared scheme, without a personal Development Team. Source builds disable code signing by default. The macOS deployment target is 15.0; that setting is not evidence of testing on every compatible Mac or OS release.

Verify releases in a clean macOS environment with Xcode and pinned packages. Offline tests do not need provider keys. Live tests require explicit opt-in and must stay outside ordinary CI. Test helper scripts require Python 3; fixture regeneration needs the additional packages listed with the fixtures.

Ad-hoc signing and codesign verification do not establish Developer ID identity or Apple notarization. Public Developer ID distribution requires the appropriate certificate, hardened runtime, secure timestamps and signatures for all nested executables, including cwebp. Notarize the distribution and verify its ticket. Keep signing keys and notarization credentials outside the repository and pull-request CI.

Official references: [Apple Developer ID](https://developer.apple.com/developer-id/), [notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [packaging](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution), [GitHub licensing](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository).
