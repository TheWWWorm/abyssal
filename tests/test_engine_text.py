"""Every engine text catalog covers the marked text, keeps its placeholders
and has the glyphs it needs."""
import pathlib, sys, unittest
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'tools'))
import engine_text
class EngineTextTests(unittest.TestCase):
    def test_catalogs_match_the_marked_text(self):
        self.assertGreater(len(engine_text.keys()),500)
        self.assertEqual(engine_text.problems(),[])
    def test_every_listed_language_has_a_catalog(self):
        for code in engine_text.languages():
            self.assertTrue((engine_text.LOCALE/f'{code}.gd').is_file(),code)
    def test_bundled_fonts_are_kept_as_is(self):
        for code,(_,name) in engine_text.FONTS.items():
            self.assertEqual((engine_text.LOCALE/f'{name}.import').read_text(),'[remap]\n\nimporter="keep"\n',name)
if __name__=='__main__':unittest.main()
