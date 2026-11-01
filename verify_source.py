"""Verify a pristine source snapshot without dependencies or private access."""
import hashlib
import json
import os
import stat
from pathlib import Path

root = Path(__file__).resolve().parent
manifest = json.loads((root / "source-manifest.json").read_text(encoding="utf-8"))
expected = {entry["path"]: entry for entry in manifest["files"]}
if len(expected) != len(manifest["files"]):
    raise SystemExit("Duplicate manifest paths")
for name, entry in expected.items():
    target = root / name
    if not target.resolve().is_relative_to(root) or any(
        parent.is_symlink() for parent in [target, *target.parents] if parent != root.parent
    ):
        raise SystemExit(f"Unsafe path: {name}")
    content = target.read_bytes()
    # Git may materialize text as CRLF on Windows. Hash the canonical LF bytes.
    if b"\0" not in content:
        try:
            content.decode("utf-8")
            content = content.replace(b"\r\n", b"\n")
        except UnicodeDecodeError:
            pass
    if len(content) != entry["size"] or hashlib.sha256(content).hexdigest() != entry["sha256"]:
        raise SystemExit(f"Source differs: {name}")
    if os.name != "nt" and bool(target.stat().st_mode & stat.S_IXUSR) != (entry["mode"] == "100755"):
        raise SystemExit(f"File mode differs: {name}")
actual = {
    p.relative_to(root).as_posix() for p in root.rglob("*")
    if p.is_file() and p.relative_to(root).parts[0] != ".git"
}
if actual != set(expected) | {"source-manifest.json"}:
    raise SystemExit("Unexpected or missing files; verify a pristine checkout before building")
print(f"Verified {manifest['version']}: {len(expected)} files")
