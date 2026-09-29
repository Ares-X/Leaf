# Source provenance and notices

Copyright (c) 2026 Leaf contributors. New Leaf code is licensed under
AGPL-3.0-or-later; see LICENSE. Earlier MIT-licensed Leaf code remains available
under its original license in git history, with its notice retained here.

Leaf follows SumatraPDF's format-dispatch, engine-routing and lazy-page-reading approach. Portable routing behavior is taken from Sumatra's EngineCreate/EngineMupdf/EngineImages paths rather than independently redesigned. It is
not a port of Win32 UI code and is not described as a clean-room implementation.
No Win32 renderer or Windows DLL is copied into the macOS app.

| Component | Source/revision | License / use |
| --- | --- | --- |
| SumatraPDF | [012d997f6a3a5c5c97b878e1a340db3bffde8c0e](https://github.com/sumatrapdfreader/sumatrapdf/tree/012d997f6a3a5c5c97b878e1a340db3bffde8c0e) | GPLv3 overall; individual files may differ |
| PalmDbReader.cpp | [source](https://github.com/sumatrapdfreader/sumatrapdf/blob/012d997f6a3a5c5c97b878e1a340db3bffde8c0e/src/PalmDbReader.cpp) | Simplified BSD; Palm record layout reference, reimplemented in Swift |
| issue-1315.ts / MobiDoc.cpp | [fixture](https://github.com/sumatrapdfreader/sumatrapdf/blob/012d997f6a3a5c5c97b878e1a340db3bffde8c0e/tests/issue-1315.ts) | GPLv3 project; Print Replica structure/behavior reference |
| Foliate JS | [78914aef4466eb960965702401634c2cb348e9b1](https://github.com/johnfactotum/foliate-js/tree/78914aef4466eb960965702401634c2cb348e9b1) | MIT; unmodified rendering modules, build-time checkout |
| fflate | Foliate's pinned vendor/fflate.js | MIT; unmodified vendored decompressor, notice retained |
| Marked | [v15.0.12, source commit b4eb83b](https://github.com/markedjs/marked/tree/b4eb83bbb48107720d95162ccecf829ba16be91e) | MIT; published ESM from npm's versioned package |
| MuPDF | [f030eda1e472268667805f438e38cee8f1da61f8](https://github.com/ArtifexSoftware/mupdf/tree/f030eda1e472268667805f438e38cee8f1da61f8) | AGPL-3.0-or-later; selective native build and its third-party notices |
| libarchive | [libarchive.org](https://libarchive.org/) | BSD-style licenses; macOS system library |
| DjVuLibre | [upstream](https://djvu.sourceforge.net/) | GPL-2.0-or-later; linked native decoder |
| CHMLib | [upstream](https://github.com/jedwing/CHMLib) | LGPL-2.1-or-later; linked native decoder |
| libjxl | [upstream](https://github.com/libjxl/libjxl) | BSD-3-Clause; linked native decoder |
| ConvertLIT / clit | Homebrew convertlit 1.8 | GPL-2.0-or-later; tiny bundled helper for Microsoft Reader LIT → OEB/EPUB |
| Ghostscript | [upstream](https://ghostscript.com/) | Separate, optional installation; not bundled by these scripts |

Build scripts retain library notices, copyright files and Homebrew installation
receipts. Readers do not need Homebrew for the bundled native libraries. Before
redistributing binaries, package the corresponding source for the exact linked
versions and transitive dependencies, not merely links to mutable upstream trees.
This branch has no released binary and has not completed that distribution audit.

The AGPL license text is the unmodified FSF license. Do not remove publication
script blocking from reader.html: Foliate's own integration guidance requires it.
