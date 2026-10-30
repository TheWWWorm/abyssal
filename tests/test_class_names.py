"""Synthetic re-obfuscation fixtures. Original game classes are never test fixtures."""
import pathlib, shutil, subprocess, sys, tempfile, unittest
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'tools'))
from class_data import ClassData, DataError, default, evaluate
from class_names import fingerprint, mapping

SOURCE='''class {base} {{ static int seed=3; int value; }}
class {holder} extends {base} {{
  static int[] table={{1,2,3}};
  static {base} first;
  static int total;
  static {{ first=new {base}(); total=table[1]+{base}.seed; }}
  int read() {{ return value; }}
}}
'''

def compile_build(root,names):
    """The same source under other class names, as a separate obfuscation."""
    root.mkdir();path=root/'Fixture.java'
    path.write_text(SOURCE.format(**names))
    subprocess.run([shutil.which('javac'),'--release','8','-d',str(root),str(path)],check=True,capture_output=True)
    return {name:ClassData((root/(name+'.class')).read_bytes()) for name in names.values()}

@unittest.skipUnless(shutil.which('javac'),'JDK needed to compile synthetic class-file fixtures')
class ClassNameTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory();root=pathlib.Path(cls.temp.name)
        cls.reference=compile_build(root/'reference',{'base':'Pa','holder':'Pb'})
        cls.renamed=compile_build(root/'renamed',{'base':'Qx','holder':'Qy'})
        cls.table=fingerprint(cls.reference)
    @classmethod
    def tearDownClass(cls):cls.temp.cleanup()

    def test_reference_names_need_no_translation(self):
        self.assertIsNone(mapping(self.reference,self.table))

    def test_renamed_build_reads_under_reference_names(self):
        renaming=mapping(self.renamed,self.table)
        self.assertEqual(renaming.classes,{'Qx':'Pa','Qy':'Pb'})
        view=renaming.view(self.renamed['Qy'])
        self.assertEqual(view.name,'Pb')
        self.assertIn(('first','LPa;'),view.fields)
        statics={}
        for owner,cls in (('Pa',renaming.view(self.renamed['Qx'])),('Pb',view)):
            for (field,desc),(flags,_) in cls.fields.items():
                if flags&8:statics[owner,field,desc]=default(desc)
        def refuse(owner,name,desc,obj,args):
            if (owner,name,desc)==('Pa','<init>','()V'):return None
            raise DataError('Unapproved method '+owner+'.'+name)
        statics['Pa','seed','I']=3
        evaluate(view,'<clinit>','()V',[],statics,refuse)
        self.assertEqual(statics['Pb','table','[I'],[1,2,3])
        self.assertEqual(statics['Pb','total','I'],5)
        self.assertEqual(statics['Pb','first','LPa;']['_type'],'Pa')

    def test_an_older_layout_of_a_reference_class_also_matches(self):
        # The reference lists each layout a class has across the releases.
        root=pathlib.Path(self.temp.name)/'older';root.mkdir()
        (root/'Pa.java').write_text('class Pa { static int seed=3; }')
        subprocess.run([shutil.which('javac'),'--release','8','-d',str(root),str(root/'Pa.java')],check=True,capture_output=True)
        older=ClassData((root/'Pa.class').read_bytes())
        table=sorted(self.table+[row for row in fingerprint({'Pa':older}) if row not in self.table])
        (root/'Qx.java').write_text('class Qx { static int seed=3; }')
        subprocess.run([shutil.which('javac'),'--release','8','-d',str(root),str(root/'Qx.java')],check=True,capture_output=True)
        build={'Qx':ClassData((root/'Qx.class').read_bytes()),'Qy':self.renamed['Qy']}
        self.assertEqual(mapping(build,table).classes,{'Qx':'Pa','Qy':'Pb'})

    def test_unmatched_classes_cannot_take_a_reference_name(self):
        # A class only this build has (its renderer) happens to be called Pa.
        root=pathlib.Path(self.temp.name)/'extra';root.mkdir()
        (root/'Pa.java').write_text('class Pa { long frames; }')
        subprocess.run([shutil.which('javac'),'--release','8','-d',str(root),str(root/'Pa.java')],check=True,capture_output=True)
        build=dict(self.renamed);build['Pa']=ClassData((root/'Pa.class').read_bytes())
        renaming=mapping(build,self.table)
        self.assertEqual(renaming.classes,{'Qx':'Pa','Qy':'Pb','Pa':'~Pa'})
        self.assertEqual(renaming.view(build['Pa']).name,'~Pa')

if __name__=='__main__':unittest.main()
