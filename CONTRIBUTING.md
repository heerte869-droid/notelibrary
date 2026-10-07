# Contributing to NoteLibrary

Thank you for helping improve NoteLibrary. Bug reports, documentation, translations, synthetic test documents, accessibility reviews, and code are all welcome. You do not need a paid AI account to work on the offline tests.

## Set up

Use Xcode 26.3 or later with its macOS SDK on a Mac that meets Xcode's system requirements. The app's deployment target is macOS 15. From the repository root:

```sh
./scripts/build.sh
./scripts/test.sh
```

For interactive development, open `macOS/NoteLibrary.xcodeproj` and run the `NoteLibrary` scheme. The main source is in `macOS/NoteLibrary`; regression tests are in `Tests`. Third-party code and licenses are documented in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Use a separate development library. In the Xcode scheme's Run environment, set `NOTELIBRARY_DATA_DIR` to an absolute path for a disposable directory outside the repository. Set `NOTELIBRARY_DISABLE_CODEX_AUTOCONNECT=1` when you do not intend to use the local Codex connection. Populate the library with original synthetic material. A test library must not point to a personal or production library.

## Report a problem

Include the app version, macOS version, steps to reproduce, expected behavior, and what happened. For provider problems, include the protocol, model identifier, and a sanitized error message. Account permissions and service capabilities can vary, so distinguish a live request from a mocked test.

Do not attach API keys, authorization headers, complete request logs, account identifiers, signed download URLs, personal source documents, or library databases. Reproduce document problems with a small synthetic file whenever possible. Crop screenshots to the relevant application area and check their content and metadata before sharing.

Report suspected vulnerabilities using the route described in [SECURITY.md](SECURITY.md). Do not post an exploit containing credentials or private data in a public issue.

## Propose a change

For a substantial feature or redesign, describe the user problem and proposed scope in an issue before implementation. Small, focused fixes can go directly into a pull request.

A useful pull request explains:

- The concrete problem and the resulting behavior.
- How the change was verified, including any checks that could not run.
- Effects on existing libraries, provider requests, and adjacent controls.
- Any dependency, license, or data-handling change.

Keep unrelated refactoring separate. Do not include generated app bundles, local settings, test results, private diagnostics, or credentials. Avoid absolute paths tied to a particular machine.

## Test the behavior that changed

Add a targeted regression test for state changes, parsing, persistence, and error handling where appropriate. Prefer protocol fixtures and original synthetic documents. If you add or run a live API test, require explicit opt-in and use only your own authorized configuration. Such tests may cost money and are not required for ordinary contributions.

For UI changes, inspect the running macOS app as well as building it. Preserve keyboard interaction, focus, cancellation, dark mode, and Reduce Motion where relevant. A successful build or a static screenshot alone does not establish that an interaction works well.

Provider changes should preserve custom endpoints, explicit user options, cancellation, and the distinction between protocol errors and authentication or quota failures. Do not weaken validation to turn an invalid reply into a successful save.

## AI-assisted contributions

NoteLibrary has been developed with AI assistance. AI tools may also be used for contributions, but the submitting contributor is responsible for understanding and reviewing the result.

Check correctness, applicable licenses, dependency changes, and whether generated fixtures or documents contain secrets or personal information. State material AI assistance in the pull request when it helps reviewers understand how the change was produced. Do not present generated claims, invented tests, or suggested citations as verified evidence.

Do not send another person's notes, credentials, or private issue content to an external AI service without their authorization. An automated review or secret scan is useful evidence, not a guarantee of safety.

## Licensing and conduct

Submit only material you have the right to contribute. By contributing, you agree that your contribution is distributed under the repository's [MIT License](LICENSE), except for clearly identified third-party material carrying its own compatible terms. Preserve attribution and license notices when modifying bundled code or assets.

Keep discussions specific, respectful, and focused on improving the app. Explain tradeoffs and make it easy for a new contributor to understand the next step.
