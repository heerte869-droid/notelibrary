# Original demonstration material

`water-cycle.md` and `demo-library.json` are original synthetic examples, licensed with the project. The library has six notebooks and eight notes covering science, reading, mathematics, design, writing, and ideas. They contain no personal library, provider account, or working API configuration. The examples are prewritten to demonstrate the bookshelf, reading and review; they are not evidence of a live AI generation result.

To try an isolated demo after building:

```sh
./scripts/build.sh
python3 scripts/make_demo.py .build/release/Build/Products/Release/NoteLibrary.app
```

Open the `NoteLibrary Demo.app` path printed by the second command. It uses a separate bundle identifier and a fresh temporary data directory. It does not replace an installed NoteLibrary app or connect automatically to Codex. It has no configured provider keys. Reading and review work without an AI account.

The command prints its temporary directory so you can delete it after quitting the demo. Changes made in the demo belong to that directory only. To import the source into a normal library instead, use the app's import action with `water-cycle.md`.
