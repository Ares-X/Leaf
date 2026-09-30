#!/usr/bin/env python3
"""Bundle runtime dylibs and generate Info.plist for the local app."""
import plistlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
contents = Path(sys.argv[1]).resolve()
core = "--core" in sys.argv[2:]
frameworks = contents / "Frameworks"
licenses = contents / "Resources" / "Licenses"
frameworks.mkdir(parents=True, exist_ok=True)
licenses.mkdir(parents=True, exist_ok=True)
shutil.copy(root / "LICENSE", licenses / "Leaf-AGPL-3.0.txt")
shutil.copy(root / "THIRD_PARTY.md", licenses / "THIRD_PARTY.md")

def run(*args):
    return subprocess.check_output([str(x) for x in args], text=True)

def macho(source):
    ident = set(run("otool", "-D", source).splitlines()[1:])
    rpaths = re.findall(r"cmd LC_RPATH\n.*?\n\s*path (.+?) \(offset", run("otool", "-l", source))
    deps = []
    for line in run("otool", "-L", source).splitlines()[1:]:
        dep = line.strip().split(" (compatibility")[0]
        if dep not in ident and not dep.startswith(("/usr/lib/", "/System/Library/")):
            deps.append(dep)
    return rpaths, deps

def resolve(source, dependency, rpaths):
    def expand(value):
        return Path(value.replace("@loader_path", str(source.parent))
                         .replace("@executable_path", str(contents / "MacOS")))
    if dependency.startswith("@rpath/"):
        tail = dependency[len("@rpath/"):]
        return next((expand(path) / tail for path in rpaths if (expand(path) / tail).is_file()), None)
    path = expand(dependency)
    return path if path.is_file() else None

copied = {}
def bundle(source):
    source = Path(source).resolve()
    if source in copied:
        return copied[source]
    target = frameworks / source.name
    if target.exists():
        raise RuntimeError(f"Duplicate dylib name: {source.name}")
    copied[source] = target
    shutil.copy2(source, target)
    target.chmod(0o755)
    rpaths, deps = macho(source)
    for dependency in deps:
        resolved = resolve(source, dependency, rpaths)
        if resolved is None:
            raise RuntimeError(f"Cannot resolve {dependency} from {source}")
        child = bundle(resolved)
        subprocess.check_call(["install_name_tool", "-change", dependency, "@loader_path/" + child.name, str(target)])
    subprocess.check_call(["install_name_tool", "-id", "@rpath/" + target.name, str(target)])
    return target

if not core:
    for name in ("MuPDF", "DjVu", "CHM", "JPEGXL"):
        source = root / "build" / "engines" / f"{name}.dylib"
        if not source.exists():
            raise RuntimeError("Missing native engines: run scripts/build-engines.sh first.")
        bundle(source)

tool = contents / "Resources" / "Tools" / "clit"
if tool.exists():
    rpaths, deps = macho(tool)
    for dependency in deps:
        resolved = resolve(tool, dependency, rpaths)
        if resolved is None:
            raise RuntimeError(f"Cannot resolve {dependency} from {tool}")
        child = bundle(resolved)
        subprocess.check_call(["install_name_tool", "-change", dependency, "@loader_path/../../Frameworks/" + child.name, str(tool)])
    subprocess.check_call(["codesign", "--force", "--sign", "-", str(tool)])

groups = re.findall(r'\(\.(\w+),\s*"([^"]+)"\)', (root / "Sources/LeafCore/Format.swift").read_text())
disabled = {"book", "markdown", "html", "mupdf", "djvu", "chm", "lit"} if core else set()
suffixes = [values for kind, values in groups if kind not in disabled]
if core:
    suffixes = [" ".join(x for x in values.split() if x != "jxl") for values in suffixes]

icon = contents / "Resources" / "Leaf.icns"
info = dict(
    CFBundleName="Leaf", CFBundleDisplayName="Leaf", CFBundleExecutable="Leaf",
    CFBundleIdentifier="dev.aresx.leaf", CFBundlePackageType="APPL",
    CFBundleShortVersionString="0.2.0", CFBundleVersion="2",
    CFBundleGetInfoString="Leaf 0.2.0", NSHumanReadableCopyright="© 2026 Leaf contributors",
    LSApplicationCategoryType="public.app-category.productivity",
    LSMinimumSystemVersion="13.0", NSHighResolutionCapable=True,
    CFBundleDocumentTypes=[dict(
        CFBundleTypeName="Readable documents", CFBundleTypeRole="Viewer", LSHandlerRank="Alternate",
        CFBundleTypeExtensions=sorted(set(" ".join(suffixes).split()))
    )],
    LSSupportsOpeningDocumentsInPlace=True,
    **({"CFBundleIconFile": "Leaf.icns"} if icon.exists() else {})
)
with (contents / "Info.plist").open("wb") as f:
    plistlib.dump(info, f)

for target in copied.values():
    subprocess.check_call(["codesign", "--force", "--sign", "-", str(target)])
print(f"{len(copied)} decoder dylibs bundled.")
