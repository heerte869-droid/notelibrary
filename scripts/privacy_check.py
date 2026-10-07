#!/usr/bin/env python3
"""Read-only release-tree check. JSONL findings contain no matched values.

Usage: python3 scripts/privacy_check.py [public-tree]
Exit 0: no findings. Exit 1: findings. Exit 2: invalid input.
This complements, rather than replaces, a Git-history secret scanner and review.
"""

from __future__ import annotations

import argparse
import io
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import stat
import struct
import sys
import zipfile
import zlib


MAX_FILE = 32 * 1024 * 1024
MAX_ARCHIVE_TOTAL = 64 * 1024 * 1024
MAX_ARCHIVE_MEMBERS = 4096
MAX_METADATA = 1024 * 1024

PRIVATE_DIRS = {
    "credentials", "ai workspace", "snapshots", "backups", "qadata",
    "deriveddata", ".build", "build", "artifacts", "xcuserdata", ".codex",
    ".claude", ".venv", "venv", "__pycache__", ".pytest_cache",
}
PRIVATE_NAMES = {"api-keys.json", "auth.json", ".ds_store", "cookies.txt"}
PRIVATE_SUFFIXES = (
    ".sqlite", ".sqlite3", ".sqlite-wal", ".sqlite-shm", ".sqlite3-wal",
    ".sqlite3-shm", ".db", ".db-wal", ".db-shm", ".keychain",
    ".keychain-db", ".pem", ".key", ".p12", ".pfx", ".mobileprovision",
    ".provisionprofile", ".log", ".xcresult", ".xcarchive", ".dsym",
    ".app", ".dmg", ".ipa", ".trace", ".pyc", ".pyo",
)
PRIVATE_REPORT = re.compile(
    r"(?:_qa_20\d{6}|^(?:clean_install|rollback)_.*20\d{6}|"
    r"^synthetic-wire-|^diagnostic-.*-(?:request|response)\.|^live-.*-results\.)",
    re.IGNORECASE,
)
RULES = (
    ("personal-absolute-path", re.compile(r"/(?:Users|home)/[^/\s\"'<>\\]+")),
    ("personal-windows-path", re.compile(r"[A-Za-z]:[\\/]Users[\\/][^\\/\s\"'<>]+")),
    ("private-system-temp-path", re.compile(r"/(?:private/)?var/folders/[A-Za-z0-9_/.-]+")),
    ("private-key", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |DSA |ENCRYPTED )?PRIVATE KEY-----")),
    ("provider-token", re.compile(r"\b(?:sk-[A-Za-z0-9_-]{20,}|tvly-[A-Za-z0-9_-]{20,}|gsk_[A-Za-z0-9]{20,})\b")),
    ("github-token", re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{25,}|github_pat_[A-Za-z0-9_]{20,})\b")),
    ("cloud-access-key", re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b")),
    ("google-api-key", re.compile(r"\bAIza[A-Za-z0-9_-]{30,}\b")),
    ("slack-token", re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{20,}\b")),
    ("credential-in-url", re.compile(r"https?://[^\s/@:\"'<>]+:[^\s/@\"'<>]+@")),
)
ASSIGNMENT = re.compile(
    r"(?i)(?:api[_-]?key|access[_-]?token|secret|password|authorization)"
    r"[\"']?\s*[:=]\s*[\"'](?:Bearer\s+)?([A-Za-z0-9_+/=-]{24,})[\"']"
)
IDENTIFYING_EXIF = {
    270, 271, 272, 306, 315, 33432, 34853, 36867, 36868, 37500, 37510,
    42016, 42032, 42033, 42035, 42036, 42037,
}
EXIF_POINTERS = {34665, 34853, 40965}
OFFICE_AUTHOR_TAGS = {"creator", "lastModifiedBy"}
PUBLIC_TEMPLATE_AUTHORS = {"python-docx", "openpyxl", "python-pptx", "Steve Canny", "scanny", "NoteLibrary"}


class Check:
    def __init__(self) -> None:
        self.findings: set[tuple[str, int, str]] = set()

    def add(self, path: str, line: int, category: str) -> None:
        self.findings.add((path, line, category))

    def text(self, data: bytes, path: str, binary: bool = False) -> None:
        encodings = ("utf-8", "utf-16-le", "utf-16-be") if binary else ("utf-8-sig",)
        for encoding in encodings:
            content = data.decode(encoding, errors="ignore")
            for category, pattern in RULES:
                for match in pattern.finditer(content):
                    if category == "credential-in-url" and path.startswith("Tests/"):
                        userinfo = match.group(0).split("://", 1)[1].rstrip("@")
                        host = re.split(r"[/\s\"'<>]", content[match.end():], maxsplit=1)[0]
                        if userinfo in {"user:password", "user:secret"} and host.endswith(".test"):
                            continue  # Deliberate endpoint-validation fixtures, never a real host.
                    line = 0 if binary else content.count("\n", 0, match.start()) + 1
                    self.add(path, line, category)
            for match in ASSIGNMENT.finditer(content):
                value = match.group(1)
                if value.lower().startswith(("synthetic", "test-", "test_", "example", "placeholder", "dummy", "your_")):
                    continue
                counts = {char: value.count(char) for char in set(value)}
                entropy = -sum((count / len(value)) * math.log2(count / len(value)) for count in counts.values())
                if entropy >= 3.5:
                    line = 0 if binary else content.count("\n", 0, match.start()) + 1
                    self.add(path, line, "credential-literal")

    def exif(self, data: bytes, path: str) -> None:
        if data.startswith(b"Exif\x00\x00"):
            data = data[6:]
        if len(data) < 8 or data[:2] not in (b"II", b"MM"):
            self.add(path, 0, "unreadable-image-metadata")
            return
        endian = "<" if data[:2] == b"II" else ">"
        seen: set[int] = set()

        def integer(offset: int, code: str) -> int:
            return struct.unpack_from(endian + code, data, offset)[0]

        def ifd(offset: int) -> None:
            if not offset or offset in seen:
                return
            if len(seen) >= 32 or offset < 8 or offset + 2 > len(data):
                raise ValueError
            seen.add(offset)
            count = integer(offset, "H")
            if count > 2048 or offset + 2 + count * 12 + 4 > len(data):
                raise ValueError
            for index in range(count):
                pos = offset + 2 + index * 12
                tag, kind, size = integer(pos, "H"), integer(pos + 2, "H"), integer(pos + 4, "I")
                if tag in IDENTIFYING_EXIF:
                    self.add(path, 0, "identifying-image-metadata")
                if tag in EXIF_POINTERS and kind == 4 and size == 1:
                    ifd(integer(pos + 8, "I"))
            ifd(integer(offset + 2 + count * 12, "I"))

        try:
            if integer(2, "H") != 42:
                raise ValueError
            ifd(integer(4, "I"))
        except (ValueError, struct.error):
            self.add(path, 0, "unreadable-image-metadata")
        self.text(data, path, binary=True)

    def metadata(self, data: bytes, path: str) -> None:
        if data.startswith(b"\x89PNG\r\n\x1a\n"):
            offset = 8
            while offset + 12 <= len(data):
                size = int.from_bytes(data[offset:offset + 4], "big")
                kind = data[offset + 4:offset + 8]
                if offset + 12 + size > len(data):
                    self.add(path, 0, "unreadable-image-metadata")
                    break
                payload = data[offset + 8:offset + 8 + size]
                if kind == b"eXIf":
                    self.exif(payload, path)
                elif kind in (b"tEXt", b"zTXt", b"iTXt"):
                    self.add(path, 0, "image-text-metadata")
                    self.text(payload, path, binary=True)
                    if kind == b"zTXt" and b"\x00" in payload:
                        try:
                            packed = payload.split(b"\x00", 1)[1]
                            unpacked = zlib.decompressobj().decompress(packed[1:], MAX_METADATA)
                            self.text(unpacked, path, binary=True)
                        except zlib.error:
                            self.add(path, 0, "unreadable-image-metadata")
                offset += size + 12
                if kind == b"IEND":
                    break
        elif data.startswith(b"\xff\xd8"):
            offset = 2
            while offset + 4 <= len(data):
                if data[offset] != 0xFF:
                    break
                marker = data[offset + 1]
                offset += 2
                if marker in (0xDA, 0xD9):
                    break
                if marker in (0x01, *range(0xD0, 0xD8)):
                    continue
                size = int.from_bytes(data[offset:offset + 2], "big")
                if size < 2 or offset + size > len(data):
                    self.add(path, 0, "unreadable-image-metadata")
                    break
                payload = data[offset + 2:offset + size]
                if marker == 0xE1:
                    if payload.startswith(b"Exif\x00\x00"):
                        self.exif(payload, path)
                    else:
                        self.add(path, 0, "image-text-metadata")
                elif marker in (0xED, 0xFE):
                    self.add(path, 0, "image-text-metadata")
                offset += size
        elif data.startswith((b"II*\x00", b"MM\x00*")):
            self.exif(data, path)
        elif data.startswith(b"RIFF") and data[8:12] == b"WEBP":
            offset = 12
            while offset + 8 <= len(data):
                kind = data[offset:offset + 4]
                size = int.from_bytes(data[offset + 4:offset + 8], "little")
                if offset + 8 + size > len(data):
                    self.add(path, 0, "unreadable-image-metadata")
                    break
                payload = data[offset + 8:offset + 8 + size]
                if kind == b"EXIF":
                    self.exif(payload, path)
                elif kind == b"XMP ":
                    self.add(path, 0, "image-text-metadata")
                offset += 8 + size + size % 2

    def archive(self, data: bytes, path: str) -> None:
        try:
            with zipfile.ZipFile(io.BytesIO(data)) as archive:
                members = archive.infolist()
                if len(members) > MAX_ARCHIVE_MEMBERS or sum(member.file_size for member in members) > MAX_ARCHIVE_TOTAL:
                    self.add(path, 0, "archive-scan-limit")
                    return
                for member in members:
                    name = member.filename
                    label = path + "!" + name
                    if member.is_dir():
                        continue
                    intentional_fixture = path == "Tests/Fixtures/unsafe.docx" and name == "../escape.txt"
                    if not intentional_fixture and (PurePosixPath(name).is_absolute() or ".." in PurePosixPath(name).parts or "\\" in name):
                        self.add(label, 0, "unsafe-archive-path")
                    if stat.S_ISLNK(member.external_attr >> 16):
                        self.add(label, 0, "symbolic-link")
                        continue
                    if private_path(name):
                        self.add(label, 0, "private-file")
                        continue
                    if member.flag_bits & 1:
                        self.add(label, 0, "encrypted-archive-member")
                        continue
                    if member.file_size > MAX_FILE:
                        self.add(label, 0, "file-scan-limit")
                        continue
                    payload = archive.read(member)
                    binary = b"\x00" in payload[:4096]
                    self.text(payload, label, binary=binary)
                    self.metadata(payload, label)
                    if payload.startswith(b"PK\x03\x04"):
                        self.add(label, 0, "nested-archive-needs-review")
                    if name == "docProps/core.xml":
                        self.office_authors(payload, label)
        except (zipfile.BadZipFile, RuntimeError, OSError, ValueError):
            self.add(path, 0, "unreadable-archive")

    def office_authors(self, data: bytes, path: str) -> None:
        # XML is scanned as text first. Do not resolve entities or load external data.
        content = data.decode("utf-8", errors="ignore")
        for tag in OFFICE_AUTHOR_TAGS:
            pattern = rf"<(?:[\w.-]+:)?{tag}(?:\s[^>]*)?>([^<]*)</(?:[\w.-]+:)?{tag}>"
            for match in re.finditer(pattern, content):
                value = match.group(1).strip()
                if value and value not in PUBLIC_TEMPLATE_AUTHORS:
                    self.add(path, content.count("\n", 0, match.start()) + 1, "document-author-metadata")

    def file(self, path: Path, label: str) -> None:
        try:
            descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
            with os.fdopen(descriptor, "rb") as handle:
                attributes = os.fstat(handle.fileno())
                if not stat.S_ISREG(attributes.st_mode):
                    self.add(label, 0, "nonregular-file")
                    return
                if attributes.st_size > MAX_FILE:
                    self.add(label, 0, "file-scan-limit")
                    return
                data = handle.read(MAX_FILE + 1)
                if len(data) > MAX_FILE:
                    self.add(label, 0, "file-scan-limit")
                    return
        except OSError:
            self.add(label, 0, "unreadable-file")
            return
        if data.startswith((b"PK\x03\x04", b"PK\x05\x06")):
            self.archive(data, label)
        else:
            self.text(data, label, binary=b"\x00" in data[:4096])
            self.metadata(data, label)

    def tree(self, root: Path) -> None:
        def walk_error(error: OSError) -> None:
            try:
                label = Path(error.filename or root).relative_to(root).as_posix()
            except ValueError:
                label = "."
            self.add(label, 0, "unreadable-directory")

        for current, directories, filenames in os.walk(root, followlinks=False, onerror=walk_error):
            folder = Path(current)
            for name in list(directories):
                path = folder / name
                label = path.relative_to(root).as_posix()
                if path.is_symlink():
                    self.add(label, 0, "symbolic-link")
                    directories.remove(name)
                elif name == ".git":
                    # History is checked separately by the release secret scanner.
                    if folder != root:
                        self.add(label, 0, "nested-git-history")
                    directories.remove(name)
                elif private_path(label):
                    self.add(label, 0, "private-directory")
                    directories.remove(name)
            for name in filenames:
                path = folder / name
                label = path.relative_to(root).as_posix()
                if path.is_symlink():
                    self.add(label, 0, "symbolic-link")
                elif private_path(label):
                    # Detect credential stores by name without reading their values.
                    self.add(label, 0, "private-file")
                elif name == ".git":
                    self.add(label, 0, "external-git-directory")
                elif not path.is_file():
                    self.add(label, 0, "nonregular-file")
                else:
                    self.file(path, label)

    def output(self) -> None:
        for path, line, category in sorted(self.findings):
            print(json.dumps({"path": path, "line": line, "category": category}, ensure_ascii=False))


def private_path(path: str) -> bool:
    parts = PurePosixPath(path).parts
    if parts and parts[0].lower() == "private":
        return True
    for part in parts:
        name = part.lower()
        if name in PRIVATE_DIRS or name in PRIVATE_NAMES or name.endswith(PRIVATE_SUFFIXES):
            return True
        if name.startswith("library.sqlite") or name.startswith("._"):
            return True
        if name.startswith(".env") and name != ".env.example":
            return True
        if PRIVATE_REPORT.search(name):
            return True
    return False


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", nargs="?", type=Path, default=Path(__file__).absolute().parent.parent)
    args = parser.parse_args()
    root = args.root.absolute()
    check = Check()
    # Never follow a root symlink or scan an installed app's live data store.
    if root.is_symlink() or not root.is_dir() or root == Path(root.anchor) or root == Path.home():
        check.add(".", 0, "invalid-scan-root")
    elif (root / "Library.sqlite").exists() or (root / "Credentials").exists() or private_path(root.name):
        check.add(".", 0, "private-runtime-root")
    else:
        check.tree(root)
    check.output()
    return 2 if any(category in {"invalid-scan-root", "private-runtime-root"} for _, _, category in check.findings) else int(bool(check.findings))


if __name__ == "__main__":
    sys.exit(main())
