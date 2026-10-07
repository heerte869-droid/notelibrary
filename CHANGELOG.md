# Changelog

## 0.8.15 — Initial source preview

This is the first public source preview, based on the 0.8.15 application. It includes the app, regression tests, bundled dependency notices, and original demonstration material. It does not include a personal library, provider credentials, or an official notarized installer.

### Included

- Native macOS notebooks and chapters, source import, editing, local search, and a focused reader.
- Source comparison, separate term/concept/formula cards, and book review with a local interval schedule.
- PDF, Word, Markdown, and self-contained HTML export.
- Configurable AI providers, custom endpoints, separate model assignments, image generation, and optional web search.
- Shared response validation, protocol-aware format negotiation, cancellation handling, and save checks.
- Local SQLite storage, attachment files, version records, and backups that exclude API credentials.

### Preview boundaries

The app targets macOS 15 or later and currently has a Simplified Chinese interface. Build instructions use Xcode 27. Provider capabilities and account permissions vary; protocol tests do not establish universal live compatibility. AI and search requests may incur provider charges and send the request's relevant content to the selected service.

See [Getting started](docs/GETTING_STARTED.md) and the [roadmap](docs/ROADMAP.md).
