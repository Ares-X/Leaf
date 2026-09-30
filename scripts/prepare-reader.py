#!/usr/bin/env python3
"""Stage the pinned Foliate modules actually reachable from Leaf's CHM reader."""
from pathlib import Path
import re
import shutil
import sys

# view.open() and view.search() load these three modules dynamically. All remaining
# imports are followed from source, so an upstream static dependency cannot vanish.
ENTRYPOINTS = ("view.js", "paginator.js", "fixed-layout.js", "search.js")
STATIC_IMPORT = re.compile(
    r'''(?m)^\s*(?:import\s+(?:[^'";]+?\s+from\s+)?|export\s+[^'";]+?\s+from\s+)['"](\.[^'"]+)['"]'''
)


def module_files(source):
    source = Path(source).resolve()
    pending = [source / name for name in ENTRYPOINTS]
    found = set()
    while pending:
        path = pending.pop().resolve()
        path.relative_to(source)
        if path in found:
            continue
        text = path.read_text(encoding="utf-8")  # Missing modules fail the build.
        found.add(path)
        pending.extend(path.parent / name for name in STATIC_IMPORT.findall(text))
    return sorted(path.relative_to(source) for path in found)


def prepare(source, destination):
    source, destination = Path(source).resolve(), Path(destination).resolve()
    modules = module_files(source)
    license_file = source / "LICENSE"
    if not license_file.is_file():
        raise FileNotFoundError(license_file)
    if source == destination or source in destination.parents or destination in source.parents:
        raise ValueError("Use a staging directory separate from the upstream checkout")
    # Remove old generated parsers/fflate instead of leaving stale files in the app.
    if destination.exists():
        shutil.rmtree(destination)
    for name in [*modules, Path("LICENSE")]:
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / name, target)
    return modules


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: prepare-reader.py UPSTREAM_CHECKOUT DESTINATION")
    modules = prepare(*sys.argv[1:])
    print(f"Prepared {len(modules)} Foliate CHM modules (no ebook parser fallback).")
