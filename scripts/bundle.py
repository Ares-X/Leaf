#!/usr/bin/env python3
"""Bundle only linked dylibs, rewrite their paths, and generate Finder associations."""
import json
import plistlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
contents = Path(sys.argv[1]).resolve()
core = '--core' in sys.argv[2:]
frameworks = contents / 'Frameworks'
licenses = contents / 'Resources' / 'Licenses'
frameworks.mkdir(parents=True, exist_ok=True)
licenses.mkdir(parents=True, exist_ok=True)
shutil.copy(root / 'LICENSE', licenses / 'Leaf-AGPL-3.0.txt')
shutil.copy(root / 'THIRD_PARTY.md', licenses / 'THIRD_PARTY.md')
for f in (root / 'Licenses').iterdir():
    if f.is_file(): shutil.copy(f, licenses / f.name)

def run(*args):
    return subprocess.check_output([str(a) for a in args], text=True)

copied = {}
def bundle(source):
    source = source.resolve()
    if source in copied: return copied[source]
    target = frameworks / source.name
    if target.exists() and source not in copied: raise RuntimeError(f'Duplicate dylib name: {source.name}')
    copied[source] = target
    shutil.copy2(source, target)
    target.chmod(0o755)
    # Preserve licenses and build receipts from the actual Cellar version used.
    if 'Cellar' in source.parts:
        prefix = Path(*source.parts[:source.parts.index('Cellar') + 3])
        folder = licenses / (prefix.parent.name + '-' + prefix.name)
        folder.mkdir(exist_ok=True)
        for f in prefix.iterdir():
            if f.is_file() and (f.name.startswith(('LICENSE', 'COPYING', 'NOTICE')) or f.name == 'INSTALL_RECEIPT.json'):
                shutil.copy(f, folder / f.name)
    ident = run('otool', '-D', source).splitlines()[1:]
    rpaths = re.findall(r'cmd LC_RPATH\n.*?\n\s*path (.+?) \(offset', run('otool', '-l', source))
    for line in run('otool', '-L', source).splitlines()[1:]:
        dependency = line.strip().split(' (compatibility')[0]
        if dependency in ident or dependency.startswith(('/usr/lib/', '/System/Library/')): continue
        def expand(value): return Path(value.replace('@loader_path', str(source.parent)))
        if dependency.startswith('@rpath/'):
            candidates = [expand(p) / dependency[len('@rpath/'):] for p in rpaths]
            resolved = next((p for p in candidates if p.exists()), None)
        else: resolved = expand(dependency)
        if resolved is None or not resolved.is_file(): raise RuntimeError(f'Cannot resolve {dependency} from {source}')
        child = bundle(resolved)
        subprocess.check_call(['install_name_tool', '-change', dependency, '@loader_path/' + child.name, str(target)])
    subprocess.check_call(['install_name_tool', '-id', '@rpath/' + target.name, str(target)])
    return target

if not core:
    for name in ('MuPDF', 'DjVu', 'CHM', 'JPEGXL'):
        source = root / 'build' / 'engines' / (name + '.dylib')
        if not source.exists(): raise RuntimeError('Missing engine: run scripts/build-engines.sh first, or explicitly choose --core.')
        bundle(source)
    # Keep upstream copyright/license files with the static MuPDF build too.
    mu = root / 'build' / 'deps' / 'mupdf'
    for f in mu.rglob('*'):
        if f.is_file() and f.name.upper().startswith(('COPYING', 'LICENSE', 'NOTICE')) and '.git' not in f.parts:
            dest = licenses / 'MuPDF' / f.relative_to(mu)
            dest.parent.mkdir(parents=True, exist_ok=True); shutil.copy(f, dest)
    shutil.copy(root / 'build' / 'native-dependencies.json', licenses / 'native-dependencies.json')
    shutil.copy(root / 'build' / 'mupdf-revision.txt', licenses / 'mupdf-revision.txt')

tool=contents/'Resources'/'Tools'/'clit'
if tool.exists():
    # ConvertLIT is copied as an executable; reuse bundle() for its non-system dylibs,
    # then rewrite only the executable's references.
    ident=run('otool','-D',tool).splitlines()[1:]
    for line in run('otool','-L',tool).splitlines()[1:]:
        dependency=line.strip().split(' (compatibility')[0]
        if dependency in ident or dependency.startswith(('/usr/lib/','/System/Library/')): continue
        if dependency.startswith('@loader_path/'): resolved=tool.parent/dependency[len('@loader_path/'):]
        elif dependency.startswith('@rpath/'):
            rpaths=re.findall(r'cmd LC_RPATH\n.*?\n\s*path (.+?) \(offset',run('otool','-l',tool))
            resolved=next((Path(x.replace('@loader_path',str(tool.parent)))/dependency[len('@rpath/'):] for x in rpaths if (Path(x.replace('@loader_path',str(tool.parent)))/dependency[len('@rpath/'):]).exists()),None)
        else: resolved=Path(dependency)
        if resolved is None or not resolved.is_file(): raise RuntimeError(f'Cannot resolve helper dependency {dependency}')
        child=bundle(resolved)
        subprocess.check_call(['install_name_tool','-change',dependency,'@loader_path/../../Frameworks/'+child.name,str(tool)])
    subprocess.check_call(['codesign','--force','--sign','-',str(tool)])

# Format.swift is the single source of truth, including compound suffixes.
groups = re.findall(r'\(\.(\w+),\s*"([^"]+)"\)', (root / 'Sources/LeafCore/Format.swift').read_text())
suffixes=[s for kind,s in groups if not core or kind not in ('mupdf','djvu','chm','lit','postscript')]
if core:suffixes=[' '.join(x for x in s.split() if x!='jxl') for s in suffixes]
info = dict(CFBundleName='Leaf', CFBundleDisplayName='Leaf', CFBundleExecutable='Leaf',
            CFBundleIdentifier='dev.aresx.leaf', CFBundlePackageType='APPL',
            CFBundleShortVersionString='0.2.0', CFBundleVersion='2',
            LSMinimumSystemVersion='13.0', NSHighResolutionCapable=True,
            CFBundleDocumentTypes=[dict(CFBundleTypeName='Readable documents', CFBundleTypeRole='Viewer',
                 LSHandlerRank='Alternate', CFBundleTypeExtensions=sorted(set(' '.join(suffixes).split())))],
            LSSupportsOpeningDocumentsInPlace=True)
with (contents / 'Info.plist').open('wb') as f: plistlib.dump(info, f)
for target in copied.values(): subprocess.check_call(['codesign', '--force', '--sign', '-', str(target)])
print(f'{len(copied)} decoder dylibs bundled; system frameworks are not copied.')
