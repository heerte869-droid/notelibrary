# Release checklist

## Source publication

1. Review every tracked file, dependency license, and example. Use original synthetic material in screenshots and fixtures.
2. Run `python3 scripts/privacy_check.py`, a current secret scanner against both the working tree and complete Git history, `./scripts/test.sh`, and `./scripts/build.sh`.
3. Review AI-assisted changes as ordinary untrusted contributions: inspect behavior, dependencies, error paths, and attribution. A passing build or secret scan does not establish correctness or ownership.
4. Create an archive with `git archive`, extract it into a fresh directory, and scan the extracted files again. Do not upload a working directory or application data directory.
5. Enable GitHub secret scanning and push protection where available. Review repository visibility, permissions, and the exact archive before publication.
6. Publish accurate release notes. Distinguish a source preview from an installed, signed, notarized release. Do not state that every provider model has been tested live.

The supplied workflow uses read-only repository permissions, pinned Actions, a checksum-verified scanner, and no provider credentials. Do not add private account keys to pull-request workflows. Do not use `pull_request_target` to execute untrusted contribution code.

## macOS installer

A distributable installer needs separate release work: repeatable build provenance, Developer ID signing, notarization, license notices, and tests on supported machines. Inspect distributed binaries and debug information for embedded developer paths. An ad-hoc local signature is not a notarized release.

Until that work is complete, distribute source and describe local-build requirements clearly. Keep build logs and diagnostics private unless independently sanitized.

## If a secret is exposed

Revoke or rotate it immediately. Deleting a file or making a repository private does not revoke a credential, remove forks, or erase downloaded copies. Follow GitHub's sensitive-data removal process after containment and coordinate with the affected provider.

References: [GitHub secret scanning](https://docs.github.com/en/code-security/concepts/secret-security/secret-scanning), [push protection](https://docs.github.com/en/code-security/concepts/secret-security/push-protection), [removing sensitive data](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository), [secure Actions use](https://docs.github.com/en/actions/reference/security/secure-use).
