"""Synthetic class-data fixtures. Original game classes are never test fixtures."""
import pathlib, shutil, subprocess, sys, tempfile, unittest
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'tools'))
from class_data import ClassData, DataError, Reader, default, evaluate, modified_utf8

@unittest.skipUnless(shutil.which('javac'),'JDK needed to compile synthetic class-file fixtures')
class ClassDataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory();cls.root=pathlib.Path(cls.temp.name)
        code='''class LiteralFixture {
          static int[][] rows = {{2,3},{5,7}};
          static String label="A\\u0000\\ud83d\\ude80";
          static int sum;
          static { for(int i=0;i<4;i++) sum+=i; }
        }
        class ForbiddenFixture { static String secret=System.getenv("PRIVATE_TEST_VALUE"); }
        class BudgetFixture { static int sum; static { for(int i=0;i<1000000;i++) sum+=i; } }
        '''
        path=cls.root/'LiteralFixture.java';path.write_text(code)
        subprocess.run([shutil.which('javac'),'--release','8',str(path)],check=True,capture_output=True)
    @classmethod
    def tearDownClass(cls):cls.temp.cleanup()
    def analyze(self,name,limit=100000):
        data=ClassData((self.root/(name+'.class')).read_bytes());fields={}
        for (field,desc),(flags,attrs) in data.fields.items():
            if flags&8:fields[name,field,desc]=data.constant(Reader(attrs['ConstantValue']).u2()) if 'ConstantValue' in attrs else default(desc)
        def reject(owner,method,desc,obj,args):raise DataError('Unapproved method '+owner+'.'+method)
        evaluate(data,'<clinit>','()V',[],fields,reject,limit)
        return fields
    def test_literal_arrays_and_loop_data(self):
        fields=self.analyze('LiteralFixture')
        self.assertEqual(fields['LiteralFixture','rows','[[I'],[[2,3],[5,7]])
        self.assertEqual(fields['LiteralFixture','sum','I'],6)
        self.assertEqual(fields['LiteralFixture','label','Ljava/lang/String;'],'A\0🚀')
    def test_external_calls_fail_closed(self):
        with self.assertRaisesRegex(DataError,'Unapproved method'):self.analyze('ForbiddenFixture')
    def test_instruction_limit(self):
        with self.assertRaisesRegex(DataError,'budget'):self.analyze('BudgetFixture',100)
    def test_truncated_file(self):
        with self.assertRaises(DataError):ClassData(b'\xca\xfe\xba\xbe')
    def test_modified_utf8(self):self.assertEqual(modified_utf8(b'a\xc0\x80b'),'a\0b')

if __name__=='__main__':unittest.main()
