# Architecture

NoteLibrary is a native macOS app built with SwiftUI and AppKit. It targets macOS 15+. There is no hosted NoteLibrary backend or mandatory developer-owned API account.

| Area | Location | Responsibility |
| --- | --- | --- |
| App state | `macOS/NoteLibrary/Core/AppModel.swift` | Library selection, persistence, and user operations |
| Models and storage | `macOS/NoteLibrary/Core/` | Typed content blocks, SQLite state, attachments, import/export, search, review |
| AI requests | `macOS/NoteLibrary/AI/` | Provider routing, local Codex connection, HTTP transports and response normalization |
| Native UI | `macOS/NoteLibrary/Views/` | Bookshelf, reader, cards, conversations, settings and exports |
| Vendored SDK | `Vendor/OpenAI/` | Pinned upstream SDK and documented local changes |
| Regression tests | `Tests/NoteLibraryTests/` | Synthetic import/export, state, protocol, search and content tests |

The database stores a versioned JSON library state in SQLite. Attachments live alongside it. A note contains typed blocks, not a single Markdown string; Markdown and Word are export formats. Credentials live in a separate local store and are excluded from library backup/export.

## AI boundary

An AI response is parsed and validated before applying supported library changes. Shared protocol adapters normalize text, structured output, errors and image results. Capability assignments determine which model performs a task. They do not prove that a remote account has access to that capability.

For provider work, prefer protocol-level fixes with small synthetic fixtures over branches tied to one account. Never add an API key, personal source material, or captured production response to a fixture. Read [PRIVACY.md](../PRIVACY.md) before changing data flows.

## Isolated development

`NOTELIBRARY_DATA_DIR` selects a separate data directory. The shared test scheme sets it to a test-host directory inside Xcode's build area. `NOTELIBRARY_DISABLE_CODEX_AUTOCONNECT=1` suppresses automatic local Codex connection for the test host. The same flag is available as the `NoteLibraryDisableCodexAutoConnect` Boolean in a local demo bundle's Info.plist.

These options isolate tests and demonstrations. They are not a network sandbox, and they do not replace reviewing any request a test explicitly makes. The public test suite uses synthetic content and mocked provider responses rather than real accounts.
