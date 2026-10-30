"""Read a re-obfuscated DEEP build under the reference build's class names.

The phone editions were compiled from one source and obfuscated separately, so
the same class can be `ah` in one JAR and `ai` in another while its fields and
methods keep their order and types. The declarative content profile is written
in the Sony Ericsson 1.0.8 names. A JAR whose classes match the reference
fingerprint by structure alone is read through a renaming view; no class is
loaded, linked or run.

The fingerprint (reference_classes.py) holds only obfuscated class and member
names and a digest of each class's member layout, never game content. The Sony
Ericsson releases share one naming, so the fingerprint lists every layout a
class has across them, and an older build matches the release it came from.
Regenerate it with `python3 tools/class_names.py JAR [JAR...]`.
"""
import hashlib, re
from class_data import ClassData

APPLICATION = re.compile(r'L(?!java/|javax/)([^;]+);')


def layout(cls):
    """Member flags and descriptors in declaration order, with application
    class names abstracted, so the digest survives renaming."""
    def abstract(desc): return APPLICATION.sub('L*;', desc)
    fields = [f'{flags}:{abstract(desc)}' for (name, desc), (flags, _) in cls.fields.items()]
    methods = [f'{flags}:{name if name.startswith("<") else ""}:{abstract(desc)}' for (name, desc), (flags, _) in cls.methods.items()]
    return hashlib.sha256('\n'.join(fields+['--']+methods).encode()).hexdigest()[:16]


def fingerprint(classes):
    return sorted([name, layout(cls), [n for n, _ in cls.fields], [n for n, _ in cls.methods]] for name, cls in classes.items())


def mapping(classes, reference):
    """Map this JAR's class names to the reference names by layout. Returns
    None when the JAR already uses the reference names for every class both
    share, so builds that need no translation are read exactly as before."""
    by_layout = {digest: (name, fields, methods) for name, digest, fields, methods in reference}
    own = {name: layout(cls) for name, cls in classes.items()}
    if all(by_layout.get(digest, (None,))[0] == name for name, digest in own.items() if digest in by_layout):
        return None
    counts = {}
    for digest in own.values(): counts[digest] = counts.get(digest, 0)+1
    names = {}
    for name, digest in own.items():
        if digest in by_layout and counts[digest] == 1: names[name] = by_layout[digest]
    # Classes with no reference counterpart (the renderer) keep a name that
    # cannot collide with a reference class.
    renamed = {name: names[name][0] if name in names else '~'+name for name in classes}
    members = {}
    for name, cls in classes.items():
        if name not in names: continue
        _, fields, methods = names[name]
        members[renamed[name]] = (dict(zip(cls.fields, fields)), dict(zip(cls.methods, methods)))
    return Renaming(renamed, members, {name: cls.super for name, cls in classes.items()})


class Renaming:
    def __init__(self, classes, members, parents):
        self.classes, self.members, self.parents = classes, members, parents

    def type(self, name):
        if name.startswith('['): return self.descriptor(name)
        return self.classes.get(name, name)

    def descriptor(self, desc):
        return APPLICATION.sub(lambda m: 'L'+self.classes.get(m.group(1), m.group(1))+';', desc)

    def member(self, owner, name, desc, kind):
        """kind 0: field, 1: method. A member reached through a subclass is
        declared on a superclass; one outside the JAR keeps its name."""
        seen = set()
        while owner in self.parents and owner not in seen:
            seen.add(owner)
            table = self.members.get(self.type(owner))
            if table and (name, desc) in table[kind]: return table[kind][name, desc], self.descriptor(desc)
            owner = self.parents[owner]
        return name, self.descriptor(desc)

    def view(self, cls):
        return RenamedClass(cls, self)


class RenamedClass:
    """The accessors the restricted evaluator uses, answered in reference names."""
    def __init__(self, cls, renaming):
        self.cls, self.renaming = cls, renaming
        self.pool = cls.pool
        self.name = renaming.type(cls.name)
        fields, methods = renaming.members.get(self.name, ({}, {}))
        self.fields = {(fields.get(k, k[0]), renaming.descriptor(k[1])): v for k, v in cls.fields.items()}
        self.originals = {(methods.get(k, k[0]), renaming.descriptor(k[1])): k for k in cls.methods}
        self.methods = {key: cls.methods[original] for key, original in self.originals.items()}

    def constant(self, index):
        value = self.cls.constant(index)
        return self.renaming.type(value) if self.cls.pool[index][0] == 7 else value

    def reference(self, index):
        owner, name, desc = self.cls.reference(index)
        kind = 0 if self.cls.pool[index][0] == 9 else 1
        name, desc = self.renaming.member(owner, name, desc, kind)
        return self.renaming.type(owner), name, desc

    def code(self, name, desc):
        return self.cls.code(*self.originals[name, desc])


def classes_of(archive):
    return {name[:-6]: ClassData(archive.read(name)) for name in archive.namelist()
            if name.endswith('.class') and '/' not in name}


if __name__ == '__main__':
    import pathlib, pprint, sys, zipfile
    table = []
    for path in sys.argv[1:]:
        with zipfile.ZipFile(path) as archive:
            table += [row for row in fingerprint(classes_of(archive)) if row not in table]
    table.sort()
    digests = [digest for _, digest, _, _ in table]
    if len(digests) != len(set(digests)): sys.exit('Two classes share one layout; the JARs do not share a naming.')
    target = pathlib.Path(__file__).with_name('reference_classes.py')
    target.write_text('"""Generated by class_names.py from the reference DEEP JARs: obfuscated\n'
                      'names and member-layout digests only."""\nCLASSES = '+pprint.pformat(table, width=120, compact=True)+'\n')
    print('Wrote', len(table), 'classes to', target)
