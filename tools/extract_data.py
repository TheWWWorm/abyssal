"""Declarative content profile for the restricted class-data reader.

The profile is written against the Sony Ericsson release of DEEP 1.0.8, the build
this engine is developed on. Other DEEP builds are converted whenever their data
layout still matches; a build that does not match fails with an explicit message
rather than being rejected up front.

Only table initializers, resource registrations and campaign/radio definitions
are evaluated. Original constructors and methods are NOT invoked: the small
record operations below are inert schema summaries. No bytecode is emitted.
"""
import hashlib, json, math, pathlib, re, zipfile
from class_data import ClassData, DataError, Reader, default, evaluate, modified_utf8

TYPES={'I':'int','S':'short','B':'byte','Z':'boolean','J':'long','F':'float','D':'double','C':'char','Ljava/lang/String;':'java.lang.String'}
def field_name(name,desc):return name+':'+TYPES.get(desc,desc.replace('/','.'))
def record(obj):
    return {field_name(k[0],k[1]):bool(v) if k[1]=='Z' else v for k,v in obj.items() if isinstance(k,tuple) and (k[1] in TYPES or k[1].startswith('['))}
def table_rows(root):
    out={}
    for name in ('ships','equipment','goods','stations','creatures'):
        rows=[]
        for row in re.sub(r'[\r\n\t]','',(root/'data/txt'/f'{name}.txt').read_text()).split(';'):
            if not row:continue
            cells=row.split(',')
            if name=='stations':rows.append([cells[0],*map(int,cells[1:])])
            elif name=='goods':rows.append([*map(int,cells[:7]),*[list(map(int,c.split())) for c in cells[7:]]])
            else:rows.append(list(map(int,cells)))
        out[name]=rows
    return out

PROFILE_CLASSES=('ah','e','bo','ab','f','dj','cy')
UNMATCHED=('This DEEP build does not match the declarative content profile, which is '
           'written for the Sony Ericsson release of DEEP 1.0.8: ')

def language_root(root):
    """Each build ships one localisation; prefer English when several are present."""
    languages=sorted(path for path in (root/'data/lang').iterdir() if path.is_dir())
    if not languages:raise DataError(UNMATCHED+'no localisation under data/lang')
    return next((path for path in languages if path.name=='en'),languages[0])

def extract(jar,root):
    try:return read_profile(jar,root)
    except DataError:raise
    except (OSError,ValueError,KeyError,IndexError,TypeError,AttributeError) as error:
        raise DataError(UNMATCHED+f'{type(error).__name__}: {error}') from error

def read_profile(jar,root):
    root=pathlib.Path(root);tables=table_rows(root)
    with zipfile.ZipFile(jar) as archive:
        present=set(archive.namelist())
        missing=[name for name in PROFILE_CLASSES if name+'.class' not in present]
        if missing:raise DataError(UNMATCHED+'missing '+', '.join(name+'.class' for name in missing))
        classes={name:ClassData(archive.read(name+'.class')) for name in PROFILE_CLASSES}
    statics={}
    for owner,cls in classes.items():
        for (name,desc),(flags,attrs) in cls.fields.items():
            if flags&8:statics[owner,name,desc]=cls.constant(Reader(attrs['ConstantValue']).u2()) if 'ConstantValue' in attrs else default(desc)
    statics['al','a','Lal;']={'_type':'al',('a','I'):-1,('b','Z'):False,('e','Z'):False}
    statics['ap','b','I']=1 # Inert locale preference input, not application state.
    textures={};models=[];active={};changes=[]
    def summary(owner,name,desc,obj,args):
        nonlocal active
        if owner=='java/lang/StringBuffer':
            if name=='<init>':obj['text']=str(args[0]) if args and isinstance(args[0],str) else '';return None
            if name=='append':obj['text']+=str(args[0]);return obj
            if name=='toString':return obj['text']
        if owner=='cd' and name=='a':
            if desc=='(ILjava/lang/String;)V':textures[args[0]]=args[1].lstrip('/')+'.bmp';return None
            if desc in ('(ILjava/lang/String;II)V','(ILjava/lang/String;I)V'):
                models.append({'id':args[0],'model':args[1].lstrip('/')+'.mbac','texture_id':args[-1]});return None
        if owner=='al':
            if name=='<init>' and desc=='(III)V':
                kind,reward,destination=args
                obj.update({('a','I'):kind,('c','I'):reward,('e','I'):destination,('b','Ljava/lang/String;'):tables['stations'][destination][0],('g','I'):-1,('h','I'):-1,('b','Z'):True,('e','Z'):True});return None
            if name=='a' and desc=='(III)V':
                species,total,minimum=args
                obj.update({('n','I'):species,('o','I'):total,('p','I'):minimum,('q','I'):int(minimum*100/total) if total else 0});return None
            if name=='a' and desc=='(II)V':obj.update({('l','I'):args[0],('m','I'):args[1]});return None
        if owner=='dj':
            if name=='c' and desc=='(Lal;)V':active=args[0];active['b','Z']=True;return None
            if name=='c' and desc=='()Lal;':return active
            if name=='a' and desc=='([I)V':changes.extend(args[0]);return None
            if name in ('j','o') and desc=='()I':return 0 # Relative progress baselines are resolved by the native campaign.
        if owner=='dt' and name=='c' and desc=='(II)I':return min(args)
        if owner=='dk' and name=='<init>' and desc in ('(IIII)V','(III[I)V'):
            obj.update({'text_id':args[0],'speaker':args[1],'kind':args[2],'values':args[3] if isinstance(args[3],list) else [args[3]]});return None
        raise DataError(f'Call is not an approved data summary: {owner}.{name}{desc}')
    for owner in ('ah','e','bo','ab','f'):
        evaluate(classes[owner],'<clinit>','()V',[],statics,summary)
    evaluate(classes['ah'],'e','()V',[],statics,summary)
    for model in models:
        model['textures']=[textures[model['texture_id']]]
        for name in [model['model'],*model['textures']]:
            if not (root/name).is_file():raise DataError('Missing registered resource: '+name)
    (root/'resource_registry.json').write_text(json.dumps(models,separators=(',',':')))
    (root/'bindings.json').write_text(json.dumps({r['model']:r['textures'] for r in models},separators=(',',':')))
    geometry={}
    for model in models:
        if not 3300<=model['id']<3400:continue
        mesh=json.loads((root/(model['model']+'.json')).read_text())
        transforms=[];points=[];cursor=0
        for bone in mesh['bones']:
            local=bone['matrix'];parent=bone['parent']
            if parent>=0:
                a=transforms[parent];matrix=[]
                for row in range(3):
                    for column in range(4):
                        matrix.append(sum(a[row*4+k]*local[k*4+column] for k in range(3))+(a[row*4+3] if column==3 else 0))
            else:matrix=local
            transforms.append(matrix)
            for _ in range(bone['vertices']):
                point=mesh['vertices'][cursor:cursor+3];cursor+=3
                points.append([sum(matrix[row*4+k]*point[k] for k in range(3))+matrix[row*4+3] for row in range(3)])
        if points:
            low=[min(p[axis] for p in points) for axis in range(3)];high=[max(p[axis] for p in points) for axis in range(3)]
            geometry[str(model['id'])]={'center':[(a+b)/2 for a,b in zip(low,high)],'extent':[max(500,(b-a)/2) for a,b in zip(low,high)]}
    constants={owner:{field_name(name,desc):value for (cls,name,desc),value in statics.items() if cls==owner and value is not None and (desc in TYPES or desc.startswith('['))} for owner in ('ah','e','bo','ab','f')}
    # Trigonometry is a numeric convention, not proprietary lookup content.
    constants['dt']={'a:[S':[round(math.sin(i*math.tau/4096)*4096) for i in range(1025)]}
    campaign=[];timelines={}
    chapters=len(constants['e']['g:[S'])
    for chapter in range(1,chapters+1):
        statics['dj','v','I']=chapter-1;active={};changes.clear()
        evaluate(classes['dj'],'c','()V',[],statics,summary)
        campaign.append({'chapter':chapter,'mission':record(active),'rebel_stations':sorted(set(changes))})
        events=evaluate(classes['cy'],'a','(I)[Ldk;',[{'_type':'cy',('a','[Law;'):[None]},chapter],statics,summary)
        if events:timelines[str(chapter)]=[{k:v for k,v in row.items() if k!='_type'} for row in events]
    strings=[];language=language_root(root)
    for name in ['main','ships','cargo','items','medals',*map(str,range(chapters-1))]:
        r=Reader((language/f'{name}.lang').read_bytes())
        while r.offset<len(r.data):strings.append(modified_utf8(r.take(r.u2())))
    names=[[s for s in re.sub(r'[\r\n\t]','',(root/'data/txt'/f'names_human_{gender}.txt').read_text()).split(';') if s] for gender in ('f','m')]
    # Habitat selection is engine policy; no original ecology routine is read.
    habitats=[]
    for index,station in enumerate(tables['stations']):
        species_count=len(tables['creatures']);habitat=[]
        for offset in range(min(6,species_count)):habitat.extend([(index*7+offset*5)%species_count,20])
        habitats.append(habitat)
    out={'schema':1,'jar_sha256':hashlib.sha256(pathlib.Path(jar).read_bytes()).hexdigest(),'importer':'native-6','language':language.name,'constants':constants,'tables':tables,'campaign':campaign,'timelines':timelines,'strings':strings,'name_pools':names,'habitats':habitats,'data_reader':'restricted-class-data-1','station_geometry':geometry}
    (root/'native-data.json').write_text(json.dumps(out,separators=(',',':')))
    return out

if __name__=='__main__':
    import sys
    out=extract(pathlib.Path(sys.argv[1]),pathlib.Path(sys.argv[2]));print('Extracted',len(out['campaign']),'chapters;',len(out['strings']),'strings without loading game classes')
