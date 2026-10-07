#!/usr/bin/env python3
"""Create a separate app and synthetic library; never read a user's app data."""

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import sqlite3
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path, help="A locally built NoteLibrary.app")
    parser.add_argument("--output", type=Path, help="A new directory; existing paths are refused")
    args = parser.parse_args()
    app = args.app.resolve()
    if not (app / "Contents/MacOS/NoteLibrary").is_file():
        parser.error("Expected a built NoteLibrary.app")
    root = Path(__file__).resolve().parent.parent
    if args.output:
        output = args.output.resolve()
        output.mkdir(parents=True, exist_ok=False)
    else:
        output = Path(tempfile.mkdtemp(prefix="NoteLibrary-Demo-"))
    data = output / "Library"
    (data / "Assets").mkdir(parents=True)
    state = json.loads((root / "Examples/demo-library.json").read_text())
    for asset in state["assets"]:
        name = asset["filename"]
        if Path(name).name != name:
            raise ValueError("Demo asset must be a simple filename")
        source = root / "Examples" / name
        raw = source.read_bytes()
        if hashlib.sha256(raw).hexdigest() != asset["digest"]:
            raise ValueError("Demo source digest mismatch")
        shutil.copyfile(source, data / "Assets" / name)
    with sqlite3.connect(data / "Library.sqlite") as db:
        db.execute("CREATE TABLE library (id INTEGER PRIMARY KEY CHECK(id=1), payload BLOB NOT NULL)")
        db.execute("PRAGMA user_version=1")
        db.execute("INSERT INTO library VALUES(1, ?)", (json.dumps(state, ensure_ascii=False).encode(),))
    target = output / "NoteLibrary Demo.app"
    shutil.copytree(app, target)
    info_path = target / "Contents/Info.plist"
    with info_path.open("rb") as file:
        info = plistlib.load(file)
    info.update({
        "CFBundleIdentifier": "dev.notelibrary.opensource.demo",
        "CFBundleDisplayName": "NoteLibrary Demo",
        "CFBundleName": "NoteLibrary Demo",
        "NoteLibraryWindowTitle": "NoteLibrary Demo",
        "NoteLibraryDataDirectory": str(data),
        "NoteLibraryDisableCodexAutoConnect": True,
    })
    with info_path.open("wb") as file:
        plistlib.dump(info, file)
    subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(target)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(target)], check=True)
    print(f"Demo app: {target}\nTemporary directory: {output}")


if __name__ == "__main__":
    main()
