# Privacy and data flow

NoteLibrary stores its library on your Mac. Remote AI and web search send information to the services you configure; those features are not offline processing.

## What stays on disk

The default location is `~/Library/Application Support/NoteLibrary`. A configured data directory can change this location.

The directory contains a SQLite library with notes, conversations, settings and source metadata; imported attachments; snapshots; and an AI working directory that may retain intermediate files. These files are not encrypted by NoteLibrary. The current app has no analytics or crash-reporting service operated by the project maintainer.

API keys are kept separately in `Credentials/api-keys.json`. The directory is restricted to the current user (`0700`); the file is restricted to the current user (`0600`). **The file contains plaintext keys.** These permissions do not prevent access by other software running as the same user, an administrator, or someone with access to an unlocked account. The current credential store is not a Keychain or encrypted vault.

## What is sent to services

| Feature | Data sent | Recipient |
| --- | --- | --- |
| AI conversation, note organization and explanation | Your request, app instructions, and the conversation, note excerpts, document text or images included in the task context | The selected model provider or configured custom endpoint |
| Web search | Search queries, which can be derived from your request or note context | The configured search service, or a model provider offering built-in search |
| Answers using web results | Retrieved search content and the relevant task context | The selected model provider |
| Image generation | The image prompt, which can include information from the task | The configured image service; returned image URLs are downloaded from the indicated host |
| Connection tests | Synthetic test requests and model configuration needed to exercise the selected capability | The service being tested |
| Codex integration | Task instructions and selected task material through the locally configured Codex executable | Services used by that executable and its signed-in account |

Provider credentials are used to authenticate requests. The project's image download path uses a fresh request and does not forward the provider API key to a returned image URL.

Providers set their own retention, training, regional processing and account policies. NoteLibrary cannot make a general promise about those policies, particularly for custom endpoints. Restrict the conversation context and attachments before requesting remote processing if the material should not leave your device.

## Backups, exports and deletion

App-managed backups and note exports exclude the separate credential store. Backups can still contain notes, conversations, settings and original attachments. A full manual copy of the data directory includes credentials and AI working files; keep it private.

Deleting a note is not a promise to erase every copy: the recycle bin, snapshots, attachments, exported files, system backups and provider-side records have separate lifecycles. Review those locations when removing sensitive material. Removing a local key does not revoke it at the provider; revoke it in the provider's account controls if necessary.

## Sharing a bug report

Use a small synthetic example. Check screenshots for note content, account details, file paths and keys. Do not attach your full library, credential store, raw request/response captures or an unreviewed diagnostic archive. Report security issues through the private route described in [SECURITY.md](SECURITY.md).
