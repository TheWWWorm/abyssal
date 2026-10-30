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
from class_data import ClassData, DataError, Reader, default, evaluate, literal_matrices, modified_utf8
from class_names import classes_of, mapping
from reference_classes import CLASSES as REFERENCE

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

def music_table(archive):
    """The sound manager's track list, in play order: track 0 is the menu and
    opening music, track 1 the docked one. 1.0.3 builds open with intro.mid and
    1.0.8 builds with station.mid, from the same code. Only static initializers
    that make no calls are read; anything else leaves the table unknown."""
    for name in archive.namelist():
        if not name.endswith('.class') or '/' in name:continue
        raw=archive.read(name)
        if b'.mid' not in raw:continue
        try:
            cls=ClassData(raw);owner=name[:-6];statics={}
            for (field,desc),(flags,attrs) in cls.fields.items():
                if flags&8:statics[owner,field,desc]=default(desc)
            def refuse(*call):raise DataError('call')
            evaluate(cls,'<clinit>','()V',[],statics,refuse)
        except (DataError,ValueError,KeyError,IndexError,TypeError,AttributeError):continue
        for value in statics.values():
            if isinstance(value,list) and value and all(isinstance(item,str) and re.fullmatch(r'/data/sound/[a-z0-9_]+\.mid',item) for item in value):
                return [item.rsplit('/',1)[1] for item in value]
    return []

def language_root(root):
    """Each build ships one localisation; prefer English when several are present."""
    languages=sorted(path for path in (root/'data/lang').iterdir() if path.is_dir())
    if not languages:raise DataError(UNMATCHED+'no localisation under data/lang')
    return next((path for path in languages if path.name=='en'),languages[0])

def language_strings(language,constants):
    """Read the declared text slots, as the phone's count-bounded loader does.

    Some repacks leave bytes after the last required string. They are not text
    slots: reading them would reject a usable file or shift every later ID.
    Counts come from this JAR's tables, never its version, filename or digest.
    """
    counts=[(name,len(constants[f'{field}:[Ljava.lang.String;']))
            for field,name in zip('abcde',('main','ships','cargo','items','medals'))]
    chapters=constants['a:[I']
    if len(chapters)!=len(constants['g:[S'])-1:
        raise DataError(UNMATCHED+'chapter language counts do not match the campaign')
    counts.extend((str(index),count) for index,count in enumerate(chapters))
    strings=[]
    for name,count in counts:
        if type(count) is not int or count<0:
            raise DataError(UNMATCHED+'invalid language count for '+name)
        r=Reader((language/f'{name}.lang').read_bytes())
        for index in range(count):
            offset=r.offset
            try:strings.append(modified_utf8(r.take(r.u2())))
            except (DataError,UnicodeError) as error:
                reason='truncated record' if isinstance(error,DataError) else 'invalid modified UTF-8'
                raise DataError(f'Invalid language data in {language.name}/{name}.lang '
                                f'(string {index+1} of {count}, byte {offset}): {reason}') from error
    return strings

def extract(jar,root,digest=None,prepare=None):
    """digest names the archive the player chose when a repacked readable copy
    of it is what is being read; the content is keyed by the original.
    prepare(models) converts registered resources that need the registry
    first, such as M3G models and their atlases."""
    try:return read_profile(jar,root,digest,prepare)
    except DataError:raise
    except (OSError,ValueError,KeyError,IndexError,TypeError,AttributeError) as error:
        raise DataError(UNMATCHED+f'{type(error).__name__}: {error}') from error

def midlet_version(archive):
    """MIDlet-Version from the manifest (1.0.2, 1.0.3, 1.0.8...), or ''."""
    try:manifest=archive.read('META-INF/MANIFEST.MF').decode('utf-8','replace').replace('\r\n','\n').replace('\n ','')
    except KeyError:return ''
    fields=dict(line.split(': ',1) for line in manifest.splitlines() if ': ' in line)
    version=fields.get('MIDlet-Version','').strip()
    return version if re.fullmatch(r'[0-9A-Za-z.\-]{1,16}',version) else ''

def has_converted_resource(root,name):
    """BMP atlases are stored as PNGs by the portable importer. The native
    converter also keeps the original BMP, so accept either output layout."""
    path=root/name
    if name.endswith('.mbac') and (root/(name+'.json')).is_file():return True # Converted from M3G.
    return path.is_file() or (name.endswith('.bmp') and (root/(name+'.png')).is_file())

def read_profile(jar,root,digest=None,prepare=None):
    root=pathlib.Path(root);tables=table_rows(root)
    with zipfile.ZipFile(jar) as archive:
        # A separately obfuscated edition is read under the reference names.
        found=classes_of(archive);renaming=mapping(found,REFERENCE)
        if renaming:found={renaming.type(name):renaming.view(cls) for name,cls in found.items()}
        missing=[name for name in PROFILE_CLASSES if name not in found]
        if missing:raise DataError(UNMATCHED+'missing '+', '.join(name+'.class' for name in missing))
        classes={name:found[name] for name in PROFILE_CLASSES}
        music=music_table(archive)
        version=midlet_version(archive)
    statics={}
    for owner,cls in classes.items():
        for (name,desc),(flags,attrs) in cls.fields.items():
            if flags&8:statics[owner,name,desc]=cls.constant(Reader(attrs['ConstantValue']).u2()) if 'ConstantValue' in attrs else default(desc)
    # al's private constructor leaves every other field at its Java default,
    # so the endgame's empty mission has jump fields of 0, not -1.
    statics['al','a','Lal;']={'_type':'al',('a','I'):-1,('g','I'):0,('h','I'):0,('b','Z'):False,('e','Z'):False}
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
    for model in models:model['textures']=[textures[model['texture_id']]]
    converted=prepare(models) if prepare else None
    for model in models:
        for name in [model['model'],*model['textures']]:
            if not has_converted_resource(root,name):raise DataError('Missing registered resource: '+name)
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
    language=language_root(root)
    strings=language_strings(language,constants['e'])
    # bw.a(int,boolean): each ';' ends a name, an empty one included, and text
    # after the last is ignored. The pool's size is a draw bound (ah.a), so a
    # dropped blank would shift every later sponsor name and random draw.
    names=[re.sub(r'[\r\n\t]','',(root/'data/txt'/f'names_human_{gender}.txt').read_text()).split(';')[:-1] for gender in ('f','m')]
    # Habitat selection is engine policy; no original ecology routine is read.
    habitats=[]
    for index,station in enumerate(tables['stations']):
        species_count=len(tables['creatures']);habitat=[]
        for offset in range(min(6,species_count)):habitat.extend([(index*7+offset*5)%species_count,20])
        habitats.append(habitat)
    out={'schema':1,'jar_sha256':digest or hashlib.sha256(pathlib.Path(jar).read_bytes()).hexdigest(),'importer':'native-6','language':language.name,'constants':constants,'tables':tables,'campaign':campaign,'timelines':timelines,'strings':strings,'name_pools':names,'habitats':habitats,'data_reader':'restricted-class-data-1','station_geometry':geometry}
    if music:out['music']=music
    # Shown to the player so they can tell which build a cache came from.
    if version:out['jar_version']=version
    # Models converted from JSR-184 (the Nokia edition) rather than Mascot Capsule.
    if converted:out['model_format']='m3g'
    # Optional presentation metadata. Read only a complete literal palette;
    # never evaluate the original scene setup or ecology code. A compatible
    # build without this table gets an empty one and neutral regional
    # colour; only an import from before this table has no key at all, and
    # the game asks for the JAR again before play.
    out['water_palette']=[]
    try:
        palettes=[matrix for matrix in literal_matrices(classes['cy'],'b','()V')
                  if len(matrix)==5 and all(len(row)==3 and all(0<=v<=255 for v in row) for row in matrix)]
        if len(palettes)==1:out['water_palette']=palettes[0]
    except (DataError,KeyError):pass
    (root/'native-data.json').write_text(json.dumps(out,separators=(',',':')))
    return out

if __name__=='__main__':
    import sys
    out=extract(pathlib.Path(sys.argv[1]),pathlib.Path(sys.argv[2]));print('Extracted',len(out['campaign']),'chapters;',len(out['strings']),'strings without loading game classes')
