# Roadmap

NoteLibrary focuses on a complete study workflow: source material, organized notes, reading, review, and export. This page describes proposed priorities, not shipped capabilities or delivery dates.

## First public preview

The source preview includes notebooks and chapters, source comparison, local search, review cards, multiple export formats, and configurable AI services. The current app targets macOS and primarily uses Simplified Chinese.

## Priorities

| Area | Proposed next work | Evidence needed |
| --- | --- | --- |
| First-run experience | Make building, service setup, and the first synthetic notebook easier to complete. | A new user can follow the guide without private configuration or maintainer help. |
| Provider reliability | Expand protocol fixtures and document capability differences. | Reproducible sanitized fixtures; live-account checks clearly distinguished from mocks. |
| Import and export | Add original examples covering longer tables, formulas, and mixed document layouts. | Rendered output inspected against the source, without silent content loss. |
| Accessibility | Improve keyboard navigation, focus behavior, and assistive-technology coverage. | Checks in the running macOS app, including Reduce Motion. |
| Language support | Extract interface strings and add an English interface. | Complete translations plus layout and terminology review. |
| Distribution | Prepare a repeatable release process and a signed, notarized macOS package. | Clean build, package review, and installation on a separate machine or user account. |

## Contributing to the direction

Describe the task you are trying to complete, the limitation you encounter, and a small example others can reproduce. Improvements to an existing workflow are especially useful. Localization, documentation, and test fixtures are welcome alongside code.

Cross-platform clients, cloud sync, collaboration, and new review algorithms require separate design decisions. They are not current capabilities or commitments.

See [CONTRIBUTING.md](../CONTRIBUTING.md) for how to propose and verify a change.
