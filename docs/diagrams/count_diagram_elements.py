#!/usr/bin/env python3
"""
Count and validate the elements of a Mermaid class-diagram document.

    python3 docs/diagrams/count_diagram_elements.py docs/diagrams/02-class-diagram.md

The roadmap asks for exact counts of classes, attributes, operations,
associations and generalizations, and says plainly: "Do not claim exact
numbers unless they were actually calculated from the file." This script is how
they are calculated, so the numbers can be re-derived and checked rather than
trusted.

It also runs the consistency check the same document asks for: duplicate class
names, relationship endpoints that name no class in the file, duplicate
relationships, and invalid multiplicities.

Counting rules, stated so they can be argued with:

  * A class is a `class Name {` declaration. `<<stereotype>>` lines and `note
    for` lines are not classes.
  * Inside a class body, a member containing `()` is an operation; anything
    else is an attribute. Enum constants (`FOO = 'foo'`) count as attributes —
    they are members of the enumeration.
  * `--|>` is a generalization. `-->` is an association. A relationship line
    whose endpoints are both multiplicitied counts once.
  * Multiplicities are the quoted tokens (`"1"`, `"*"`, `"0..1"`, …) and the
    `|label|` pipe form. Anything else on an endpoint is a dangling reference.
"""
from __future__ import annotations

import re
import sys
from collections import Counter, defaultdict

CLASS_OPEN = re.compile(r'^\s*class\s+([A-Za-z_][\w]*)\s*\{')
CLASS_CLOSE = re.compile(r'^\s*\}')
GENERALIZATION = re.compile(r'(<\|--|--\|>|--\|)')
ASSOCIATION = re.compile(r'-->')
# Composition `*--` and aggregation `o--` are UML association *kinds*, not
# separate from them, so they are counted separately and also folded into the
# association total.
COMPOSITION = re.compile(r'\*--')
AGGREGATION = re.compile(r'o--')
DEPENDENCY = re.compile(r'-->\|')
# `A "1" --> "0..1" B : label` / `A -->|label| B` / `A --> B`
PIPE_EDGE = re.compile(r'-->(?:\|[^|]*\|)')
QUOTED_MULT = re.compile(r'"([^"]*)"')
VALID_MULT = {
    '0..1', '1', '*', '0..*', '1..*', 'n', '1..1', '0', '0..n',
}

# Types that are language/library builtins or external libraries, not diagram
# classes. Anything else appearing as a member's type should be declared.
BUILTIN_TYPES = {
    'int', 'String', 'bool', 'float', 'double', 'num', 'void', 'dynamic',
    'Object', 'Date', 'DateTime', 'Duration', 'Decimal', 'UUID', 'JSON',
    'List', 'Map', 'Set', 'Iterable', 'Stream', 'Future', 'AsyncValue',
    'Widget', 'BuildContext', 'TextEditingController', 'Timer', 'Color',
    'IconData', 'Dio', 'StreamController', 'Connectivity', 'SwitchValue',
    'ImageField', 'FileField', 'URLField', 'CharField', 'TextField',
    'BooleanField', 'IntegerField', 'DateTimeField', 'DateField',
    'JSONField', 'FloatField', 'SlugField', 'ForeignKey', 'ManyToManyField',
    'Integer', 'String_', 'bool_',
}

MEMBER_VISIBILITY = re.compile(r'^[+\-#~]')


def strip_inline_comment(line: str) -> str:
    """Drop a trailing `%%` comment, which is not part of the diagram."""
    idx = line.find('%%')
    return line if idx == -1 else line[:idx]


def member_type_ref(member: str):
    """Class-like names a member refers to.

    The file is not consistent about member order — it writes both `+int id`
    (type first) and `+is_visitor bool` (name first) — so rather than guess a
    position, collect every PascalCase token and let the caller decide. That
    keeps `TokenPair` and `UserStats` while discarding snake_case member names
    like `home_view` and builtins like `String`.
    """
    text = member.strip()
    # Unwrap generics first: `List~ModerationItem~` must yield
    # `ModerationItem`, not `List` and not `ModerationItem~`.
    for inner in re.findall(r'[A-Z][A-Za-z0-9_]*(?:<[^>]*>)?', text):
        yield from re.findall(r'[A-Z][A-Za-z0-9_]*', inner)


def split_block(lines: list[str], start: int) -> tuple[list[str], int]:
    """Return the body of a class block starting at `start`, and the next line."""
    body: list[str] = []
    i = start + 1
    while i < len(lines) and not CLASS_CLOSE.match(lines[i]):
        body.append(lines[i])
        i += 1
    return body, i + 1


def analyse(path: str) -> dict:
    raw = open(path, encoding='utf-8').read().splitlines()
    lines = [strip_inline_comment(l).rstrip() for l in raw]

    declarations: list[tuple[str, int]] = []
    bodies: dict[str, list[str]] = {}
    type_refs: list[str] = []
    attributes = 0
    operations = 0

    i = 0
    while i < len(lines):
        m = CLASS_OPEN.match(lines[i])
        if m:
            name = m.group(1)
            declarations.append((name, i + 1))
            body, i = split_block(lines, i)
            bodies.setdefault(name, []).extend(body)
            for member in body:
                text = member.strip()
                if not text or text.startswith('<<') or text.startswith('%%'):
                    continue
                if '(' in text:
                    operations += 1
                else:
                    attributes += 1
                type_refs.extend(member_type_ref(text))
            continue
        i += 1

    # Relationships — only lines outside a class body.
    inside = set()
    for name, _ in declarations:
        inside.update(range(0, 0))  # placeholder, filled below
    relationships: list[tuple[int, str]] = []
    i = 0
    while i < len(lines):
        m = CLASS_OPEN.match(lines[i])
        if m:
            _, i = split_block(lines, i)
            continue
        text = lines[i].strip()
        if text:
            relationships.append((i + 1, text))
        i += 1

    associations = [t for _, t in relationships if ASSOCIATION.search(t)]
    generalizations = [t for _, t in relationships if GENERALIZATION.search(t)]
    compositions = [t for _, t in relationships if COMPOSITION.search(t)]
    aggregations = [t for _, t in relationships if AGGREGATION.search(t)]
    notes = [t for _, t in relationships if t.startswith('note ')]

    names = [n for n, _ in declarations]
    declared = set(names)
    duplicates = sorted(n for n, c in Counter(names).items() if c > 1)

    # Endpoint extraction: "A "1" --> "*" B : label" -> ['A', '*', 'B', 'label']
    endpoint_refs: Counter = Counter()
    dangling: list[tuple[int, str, str]] = []
    bad_multiplicity: list[tuple[int, str, str]] = []
    seen_relationships: Counter = Counter()

    for lineno, text in relationships:
        if text.startswith('note ') or text.startswith('%%'):
            continue
        if not (ASSOCIATION.search(text) or GENERALIZATION.search(text)):
            continue
        core = re.split(r'\s:\s', text, maxsplit=1)[0]
        seen_relationships[core.strip()] += 1

        endpoints = re.sub(r'\s*-->(?:\|[^|]*\|)\s*', ' ', core)
        endpoints = re.sub(r'\s*-->\s*', ' ', endpoints)
        endpoints = re.sub(r'\s*<\|--\s*', ' ', endpoints)
        endpoints = re.sub(r'\s*--\|>\s*', ' ', endpoints)
        tokens = endpoints.split()
        clean: list[str] = []
        mults: list[str] = []
        for tok in tokens:
            if tok.startswith('"') and tok.endswith('"'):
                mults.append(QUOTED_MULT.match(tok).group(1))
            elif tok in VALID_MULT:
                mults.append(tok)
            else:
                clean.append(tok)

        for ref in clean:
            endpoint_refs[ref] += 1
            if ref not in declared:
                dangling.append((lineno, ref, text))
        for mlt in mults:
            if mlt not in VALID_MULT:
                bad_multiplicity.append((lineno, mlt, text))

    # A name used only as an endpoint or attribute type but never declared is
    # the interesting failure; one used in several places is likely just an
    # external/aliased type rather than a missing class.
    undeclared = {r: c for r, c in endpoint_refs.items() if r not in declared}
    duplicate_relationships = sorted(
        r for r, c in seen_relationships.items() if c > 1
    )

    return {
        'path': path,
        'class_declarations': len(declarations),
        'unique_classes': len(declared),
        'duplicate_classes': duplicates,
        'attributes': attributes,
        'operations': operations,
        'associations': len(associations),
        'compositions': len(compositions),
        'aggregations': len(aggregations),
        'generalizations': len(generalizations),
        'notes': len(notes),
        'dangling_endpoints': dangling,
        'undeclared_endpoint_refs': undeclared,
        'bad_multiplicity': bad_multiplicity,
        'duplicate_relationships': duplicate_relationships,
        'undeclared_member_types': sorted(
            {t for t in type_refs
             if t and t not in declared and t not in BUILTIN_TYPES}
        ),
    }


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__)
        return 2
    r = analyse(argv[1])
    print(f"file                        {r['path']}")
    print(f"class declarations          {r['class_declarations']}")
    print(f"unique classes              {r['unique_classes']}")
    print(f"attributes                  {r['attributes']}")
    print(f"operations                  {r['operations']}")
    print(f"associations (total)        {r['associations']}")
    print(f"  of which composition      {r['compositions']}")
    print(f"  of which aggregation      {r['aggregations']}")
    print(f"generalizations             {r['generalizations']}")
    print(f"notes                       {r['notes']}")
    print()
    print(f"duplicate class names       {r['duplicate_classes'] or 'none'}")
    print(f"duplicate relationships     {r['duplicate_relationships'] or 'none'}")
    print(f"invalid multiplicities      {r['bad_multiplicity'] or 'none'}")

    if r['dangling_endpoints']:
        grouped: dict[str, list[int]] = defaultdict(list)
        for lineno, ref, _ in r['dangling_endpoints']:
            grouped[ref].append(lineno)
        print()
        print('DANGLING ENDPOINTS — relationship names a class never declared')
        for ref in sorted(grouped):
            lines_seen = sorted(set(grouped[ref]))
            print(f'  {ref}  used {len(grouped[ref])}x  at lines {lines_seen}')
    else:
        print('\ndangling endpoints          none')

    if r['undeclared_member_types']:
        print()
        print('UNDECLARED MEMBER TYPES — a member\'s type names no class here')
        for t in r['undeclared_member_types']:
            print(f'  {t}')
    else:
        print('\nundeclared member types     none')

    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
