# Security

## Reporting a vulnerability

Use **Security → Report a vulnerability** on this repository when private reporting is available. Include the affected version, a minimal reproduction with synthetic data, the impact, and a proposed fix if you have one.

Do not put API keys, personal notes, provider responses, credential files, or a copy of your library in a public issue. If private reporting is unavailable, open an issue asking for a private reporting channel without including exploit details or sensitive files. No response-time guarantee is currently offered.

Security fixes target the latest release and the default branch. Older builds are not maintained separately.

## Local and remote trust boundaries

- Provider keys are stored as **plaintext JSON**, with a `0700` directory and a `0600` file. This is access control, not encryption or protection from software running as your macOS user. See [PRIVACY.md](PRIVACY.md).
- Model and search requests go to the endpoints you configure. Only configure services and local executables you trust. Model output and imported documents are untrusted input.
- App-managed note backups and exports exclude the credential store, but contain the notes and other material you chose to export. A manual copy of the whole application data directory also copies credentials and working files.
- The project does not ship a shared API key. Connection tests and live requests can use your provider quota.

## Before contributing or publishing

Run `python3 scripts/privacy_check.py` against the intended public tree. It reads that tree only, does not contact a service, and reports only paths, line numbers, and finding categories. A clean run is silent; findings return a nonzero exit status.

The check covers common credential patterns, private runtime files, personal absolute paths, document archives, image metadata, and symbolic links. It does not prove that arbitrary content is non-sensitive and does not scan Git history. PDF object streams, legacy Office metadata and encrypted fixtures still need provenance or manual review. Review the staged diff, inspect screenshots with synthetic data, and run an independent secret scanner on both the tree and history. Public examples should use obvious placeholders such as `test-key`, never a working credential.

Keep live account tests opt-in and separate from ordinary CI. Do not give untrusted pull requests provider keys or signing credentials. CI should use minimum permissions and third-party actions pinned to a full commit SHA.

If a real secret is exposed, revoke or rotate it immediately. Removing the current file or making the repository private does not remove copies from existing history, clones, or forks.

References: [GitHub secret scanning](https://docs.github.com/en/code-security/concepts/secret-security/secret-scanning), [push protection](https://docs.github.com/en/code-security/concepts/secret-security/push-protection), [removing sensitive data](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository), [Actions security](https://docs.github.com/en/actions/reference/security/secure-use).
