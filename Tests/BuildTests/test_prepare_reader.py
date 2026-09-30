import importlib.util
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "prepare-reader.py"
spec = importlib.util.spec_from_file_location("prepare_reader", SCRIPT)
prepare_reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare_reader)


class PrepareReaderTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.source = Path(self.temp.name) / "upstream"
        self.source.mkdir()
        self.dest = Path(self.temp.name) / "staged"
        # The four static imports below are from the pinned Foliate view.js.
        files = {
            "view.js": "import * as CFI from './epubcfi.js'\nimport { TOCProgress, SectionProgress } from './progress.js'\nimport { Overlayer } from './overlayer.js'\nimport { textWalker } from './text-walker.js'\n",
            "epubcfi.js": "export const x = 1\n",
            "progress.js": "import './epubcfi.js'\n",
            "overlayer.js": "",
            "text-walker.js": "",
            "paginator.js": "",
            "fixed-layout.js": "",
            "search.js": "",
            "epub.js": "throw Error('Unreachable ebook parser')",
            "LICENSE": "Test license fixture",
        }
        for name, text in files.items():
            (self.source / name).write_text(text)

    def test_static_and_dynamic_reader_dependencies_are_staged(self):
        names = prepare_reader.prepare(self.source, self.dest)
        self.assertEqual(len(names), 8)
        for name in names:
            self.assertEqual((self.source / name).read_bytes(), (self.dest / name).read_bytes())
        self.assertTrue((self.dest / "LICENSE").is_file())
        self.assertFalse((self.dest / "epub.js").exists())

    def test_stale_parsers_are_removed(self):
        self.dest.mkdir()
        (self.dest / "mobi.js").write_text("stale")
        prepare_reader.prepare(self.source, self.dest)
        self.assertFalse((self.dest / "mobi.js").exists())

    def test_missing_module_fails_before_deleting_previous_stage(self):
        self.dest.mkdir()
        (self.dest / "previous.js").write_text("working")
        (self.source / "epubcfi.js").unlink()
        with self.assertRaises(FileNotFoundError):
            prepare_reader.prepare(self.source, self.dest)
        self.assertTrue((self.dest / "previous.js").is_file())

    def test_multiline_import_and_reexport_are_followed(self):
        (self.source / "search.js").write_text("import {\n x\n} from './extra.js'\nexport { y } from './export.js'\n")
        (self.source / "extra.js").write_text("")
        (self.source / "export.js").write_text("")
        self.assertEqual(len(prepare_reader.module_files(self.source)), 10)

    def test_unused_dynamic_parser_is_not_copied(self):
        with (self.source / "view.js").open("a") as file:
            file.write("const unused = () => import('./epub.js')\n")
        prepare_reader.prepare(self.source, self.dest)
        self.assertFalse((self.dest / "epub.js").exists())

    def test_cycles_are_visited_once(self):
        (self.source / "progress.js").write_text("import './view.js'\n")
        self.assertEqual(len(prepare_reader.module_files(self.source)), 8)


if __name__ == "__main__":
    unittest.main()
