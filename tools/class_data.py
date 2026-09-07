"""Restricted class-file data evaluator, implemented from the JVM specification.

Reads local bytes; never loads classes into a JVM. This is intentionally NOT a
Java runtime: calls require a caller-supplied data summary, unsupported opcodes
fail, and allocation/instruction limits bound analysis. Evaluating expressions
from original bytecode is still reverse engineering, not a clean-room claim.
"""
import re, struct

class DataError(ValueError): pass

def modified_utf8(raw):
    text=raw.replace(b'\xc0\x80',b'\x00').decode('utf-8',errors='surrogatepass')
    return text.encode('utf-16','surrogatepass').decode('utf-16')

class Reader:
    def __init__(self,data):self.data=data;self.offset=0
    def take(self,count):
        if count<0 or self.offset+count>len(self.data):raise DataError('Truncated class data')
        value=self.data[self.offset:self.offset+count];self.offset+=count;return value
    def number(self,fmt):return struct.unpack('>'+fmt,self.take(struct.calcsize(fmt)))[0]
    def u1(self):return self.number('B')
    def u2(self):return self.number('H')
    def u4(self):return self.number('I')

class ClassData:
    def __init__(self,raw):
        r=Reader(raw)
        if r.u4()!=0xcafebabe:raise DataError('Invalid class magic')
        r.u2();r.u2();count=r.u2();self.pool=[None]*count;i=1
        while i<count:
            tag=r.u1()
            if tag==1:value=modified_utf8(r.take(r.u2()))
            elif tag in (3,4,5,6):value=r.number({3:'i',4:'f',5:'q',6:'d'}[tag])
            elif tag in (7,8,16,19,20):value=r.u2()
            elif tag in (9,10,11,12,17,18):value=(r.u2(),r.u2())
            elif tag==15:value=(r.u1(),r.u2())
            else:raise DataError(f'Unsupported constant tag {tag}')
            self.pool[i]=(tag,value);i+=2 if tag in (5,6) else 1
        r.u2();self.name=self.constant(r.u2());r.u2();r.take(r.u2()*2)
        self.fields=self.members(r);self.methods=self.members(r);self.attributes=self.attrs(r)
        if r.offset!=len(raw):raise DataError('Trailing class data')
    def constant(self,index):
        tag,value=self.pool[index]
        return self.constant(value) if tag in (7,8) else value
    def reference(self,index):
        owner,member=self.constant(index);name,desc=self.constant(member)
        return self.constant(owner),self.constant(name),self.constant(desc)
    def attrs(self,r):
        out={}
        for _ in range(r.u2()):
            name=self.constant(r.u2());out[name]=r.take(r.u4())
        return out
    def members(self,r):
        out={}
        for _ in range(r.u2()):
            flags=r.u2();name=self.constant(r.u2());desc=self.constant(r.u2())
            out[name,desc]=(flags,self.attrs(r))
        return out
    def code(self,name,desc):
        r=Reader(self.methods[name,desc][1]['Code']);r.u2();locals_count=r.u2()
        return r.take(r.u4()),locals_count

def argument_types(desc):return re.findall(r'\[*L[^;]+;|\[*[ZBCSIJFD]',desc[1:desc.index(')')])
def default(desc):return None if desc.startswith(('L','[')) else 0

def evaluate(cls,name,desc,arguments,statics,summarize,limit=100000):
    code,size=cls.code(name,desc);r=Reader(code);local=[None]*size;local[:len(arguments)]=arguments;stack=[]
    def branch(offset):
        target=start+offset
        if not 0<=target<len(code):raise DataError('Invalid branch')
        r.offset=target
    for step in range(limit):
        start=r.offset;op=r.u1()
        if op==0:pass
        elif op==1:stack.append(None)
        elif 2<=op<=8:stack.append(op-3)
        elif op in (9,10,11,12,13,14,15):stack.append({9:0,10:1,11:0.,12:1.,13:2.,14:0.,15:1.}[op])
        elif op==16:stack.append(r.number('b'))
        elif op==17:stack.append(r.number('h'))
        elif op in (18,19,20):stack.append(cls.constant(r.u1() if op==18 else r.u2()))
        elif op in (21,22,23,24,25):stack.append(local[r.u1()])
        elif 26<=op<=45:stack.append(local[(op-26)%4])
        elif 46<=op<=53:
            index=stack.pop();array=stack.pop();stack.append(array[index])
        elif op in (54,55,56,57,58):local[r.u1()]=stack.pop()
        elif 59<=op<=78:local[(op-59)%4]=stack.pop()
        elif 79<=op<=86:
            value=stack.pop();index=stack.pop();array=stack.pop()
            if not 0<=index<len(array):raise DataError('Invalid literal array index')
            array[index]=value
        elif op==87:stack.pop()
        elif op==89:stack.append(stack[-1])
        elif op==90:
            a=stack.pop();b=stack.pop();stack.extend([a,b,a])
        elif op==92:stack.extend(stack[-2:])
        elif op==95:stack[-2:]=reversed(stack[-2:])
        elif op in (96,100,104,108,112,120,122,124,126,128,130):
            b=stack.pop();a=stack.pop()
            if op==96:value=a+b
            elif op==100:value=a-b
            elif op==104:value=a*b
            elif op==108:value=int(a/b)
            elif op==112:value=a-int(a/b)*b
            elif op==120:value=a<<(b&31)
            elif op==122:value=a>>(b&31)
            elif op==124:value=(a&0xffffffff)>>(b&31)
            elif op==126:value=a&b
            elif op==128:value=a|b
            else:value=a^b
            stack.append(((value+2**31)%2**32)-2**31)
        elif op==116:stack.append(-stack.pop())
        elif op==132:
            index=r.u1();local[index]+=r.number('b')
        elif op in (133,134,135,136,139,142):stack.append(float(stack.pop()) if op in (134,135) else int(stack.pop()))
        elif op in (145,146,147):
            value=stack.pop();bits=8 if op==145 else 16
            stack.append(value%(2**bits) if op==146 else (value+2**(bits-1))%(2**bits)-2**(bits-1))
        elif 153<=op<=164:
            offset=r.number('h');b=0 if op<=158 else stack.pop();a=stack.pop();kind=(op-153)%6
            if (a==b,a!=b,a<b,a>=b,a>b,a<=b)[kind]:branch(offset)
        elif op in (165,166):
            offset=r.number('h');b=stack.pop();a=stack.pop()
            if (a is b)==(op==165):branch(offset)
        elif op==167:branch(r.number('h'))
        elif op in (170,171):
            while r.offset%4:r.u1()
            fallback=r.number('i');mapping={}
            if op==170:
                low=r.number('i');high=r.number('i')
                if high-low>10000:raise DataError('Oversized switch')
                for key in range(low,high+1):mapping[key]=r.number('i')
            else:
                count=r.number('i')
                if not 0<=count<=10000:raise DataError('Oversized switch')
                for _ in range(count):
                    key=r.number('i');mapping[key]=r.number('i')
            branch(mapping.get(stack.pop(),fallback))
        elif op in (172,173,174,175,176):return stack.pop()
        elif op==177:return None
        elif op in (178,179,180,181):
            owner,field,field_type=cls.reference(r.u2());key=(owner,field,field_type)
            if op==178:
                if key not in statics:raise DataError(f'Unspecified static input {key}')
                stack.append(statics[key])
            elif op==179:statics[key]=stack.pop()
            elif op==180:
                obj=stack.pop();stack.append(obj.get((field,field_type),default(field_type)))
            else:
                value=stack.pop();obj=stack.pop();obj[field,field_type]=value
        elif op in (182,183,184):
            owner,method,signature=cls.reference(r.u2());argc=len(argument_types(signature))
            args=stack[-argc:] if argc else []
            if argc:del stack[-argc:]
            obj=None if op==184 else stack.pop()
            value=summarize(owner,method,signature,obj,args)
            if not signature.endswith('V'):stack.append(value)
        elif op==187:stack.append({'_type':cls.constant(r.u2())})
        elif op in (188,189):
            array_type=r.u1() if op==188 else r.u2();count=stack.pop()
            if not isinstance(count,int) or not 0<=count<=100000:raise DataError('Oversized literal array')
            stack.append([0 if op==188 else None for _ in range(count)])
        elif op==190:stack.append(len(stack.pop()))
        elif op==192:r.u2() # Type assertion on inert data only.
        elif op in (198,199):
            offset=r.number('h');value=stack.pop()
            if (value is None)==(op==198):branch(offset)
        else:raise DataError(f'Unsupported data opcode 0x{op:02x} in {cls.name}.{name}{desc} at {start}')
    raise DataError('Data evaluation instruction budget exceeded')
