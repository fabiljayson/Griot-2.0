#!/usr/bin/env python3
"""
Export the Mermaid blocks of a class-diagram `.md` to converter-ready `.mmd`.

    python3 docs/diagrams/export_class_diagram_mmd.py \
        docs/diagrams/02-class-diagram-improved.md \
        /tmp/mmd

Why this exists. `docs/diagrams/02-class-diagram.md` is hand-written for
readability and uses a convention a human eye likes:

    +String role: StoryStatus      ← type first, then an enumeration
    +is_published bool            ← name first, then the type
    +String language: en or fr    ← prose in the type slot, not a class

`mermaid2modelio` reads `+Type name` and resolves every type against the set of
declared classes. Fed the raw markdown it therefore reports `UNDEFINED_TYPE` for
`is_published` (it read the name as the type) and for `DateTime`, `List`,
`ImageField` and friends (real Django types, but not classes in the diagram).

The committed `mermaid/*.mmd` files show how the project already solved this:
members are normalised to `+Type name`, a prose type slot is dropped, and each
remaining non-primitive type is appended as an empty stub class. This script
does the same thing deterministically, so the transformation is reviewable and
re-runnable instead of being a one-off manual edit.

The transformation, in order:

  1. `+<prim> <name>: <Ident>`  ->  `+<name>: <Ident>`   (drop the primitive)
  2. `+<prim> <name>: <prose>`  ->  `+<name>`            (no class named)
  3. `+<name> <prim>`            ->  `+<prim> <name>`    (name-first swap)
  4. everything else             ->  unchanged
  5. append `class X {}` for every non-primitive type still referenced
     but not declared.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

PRIMITIVES = {
    'string', 'str', 'integer', 'int', 'boolean', 'bool', 'real', 'float',
    'double', 'unlimitednatural',
}

# Never a class, and never worth a stub declaration.
NOT_A_CLASS = {'void', 'self', 'this'}

BLOCK = re.compile(r'```mermaid\n(.*?)```', re.S)
CLASS_OPEN = re.compile(r'^(\s*)class\s+([A-Za-z_][\w]*)\s*\{$')
CLASS_CLOSE = re.compile(r'^\s*\}$')
MEMBER = re.compile(r'^(\s*)([+\-#~])(\S.*)$')
IDENT = re.compile(r'^[A-Za-z_][\w]*$')

# Language modifiers that sit in front of the type slot.
MODIFIERS = {
    'static', 'abstract', 'final', 'const', 'readonly', 'override',
    'virtual', 'late', 'required', 'optional',
}


def looks_like_type(token: str) -> bool:
    """A type token is a primitive or a PascalCase name; a member name is not."""
    return token.lower() in PRIMITIVES or token[:1].isupper()


def strip_modifiers(body: str) -> str:
    """Drop leading language modifiers so the next token is the type."""
    tokens = body.split()
    while tokens and tokens[0].lower() in MODIFIERS:
        tokens.pop(0)
    return ' '.join(tokens)


def strip_inline_comment(line: str) -> str:
    """Drop a trailing `%% ...` note, keeping whole-line `%%` section markers."""
    stripped = line.lstrip()
    if stripped.startswith('%%'):
        return line
    idx = line.find('%%')
    if idx == -1:
        return line
    return line[:idx].rstrip()


def normalise_member(line: str) -> tuple[str, list[str]]:
    """Return the normalised member line and the types it references."""
    m = MEMBER.match(line)
    if not m:
        return line, []

    indent, vis, rest = m.group(1), m.group(2), strip_inline_comment(m.group(3).strip())
    if not rest or rest.startswith('<<') or rest.startswith('%%'):
        return line, []

    # An operation keeps its shape; only its return type is a reference.
    if '(' in rest:
        after = rest.split(')', 1)[1].strip() if ')' in rest else ''
        refs = [after.split()[0]] if after and IDENT.match(after.split()[0]) else []
        stripped = strip_modifiers(rest)
        return (f'{indent}{vis}{stripped}' if stripped != rest else line), refs

    body, sep, annotation = rest.partition(':')
    annotation = annotation.strip()
    tokens = strip_modifiers(body).split()

    if sep:
        # `+String role: StoryStatus` / `+String language: en or fr`
        name = tokens[-1]
        if IDENT.match(annotation) and annotation.lower() not in PRIMITIVES:
            return f'{indent}{vis}{name}: {annotation}', [annotation]
        return f'{indent}{vis}{name}', []

    if len(tokens) == 2 and looks_like_type(tokens[1]) and not looks_like_type(tokens[0]):
        # Name-first property: `+is_published bool`, `+tag_list List`
        name, type_token = tokens
        return f'{indent}{vis}{type_token} {name}', [type_token]

    type_token = tokens[0]
    refs = [type_token] if IDENT.match(type_token) else []
    if len(tokens) != len(rest.split()):
        return f'{indent}{vis}{" ".join(tokens)}', refs
    return line, refs


def export(md_path: Path, out_dir: Path) -> list[Path]:
    text = md_path.read_text(encoding='utf-8')
    blocks = BLOCK.findall(text)
    if not blocks:
        raise SystemExit(f'no mermaid blocks found in {md_path}')

    out_dir.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []
    stem = md_path.stem

    for index, block in enumerate(blocks, 1):
        lines = block.splitlines()
        out: list[str] = []
        declared: set[str] = set()
        referenced: list[str] = []          # first-use order, not sorted
        seen_types: set[str] = set()
        depth = 0          # >0 while inside a class body
        in_class = False

        for line in lines:
            opening = CLASS_OPEN.match(line)
            if opening:
                declared.add(opening.group(2))
                in_class = True
                depth += 1
                out.append(line)
                continue
            if in_class and CLASS_CLOSE.match(line):
                depth -= 1
                if depth == 0:
                    in_class = False
                out.append(line)
                continue

            if in_class and depth == 1:
                new_line, refs = normalise_member(line)
                for ref in refs:
                    if ref not in seen_types:
                        seen_types.add(ref)
                        referenced.append(ref)
                out.append(new_line)
                continue

            out.append(line)

        stubs = [
            r for r in referenced
            if r not in declared
            and r.lower() not in PRIMITIVES
            and r.lower() not in NOT_A_CLASS
        ]
        if stubs:
            out.append('')
            for stub in stubs:
                out.extend(('', f'    class {stub} {{', '    }'))

        target = out_dir / f'{stem}.{index:02d}.mmd'
        target.write_text('\n'.join(out) + '\n', encoding='utf-8')
        written.append(target)
        print(
            f'{target}  classes={len(declared)} '
            f'stub_types={len(stubs)}  lines={len(out)}'
        )

    return written


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__)
        return 2
    export(Path(argv[1]), Path(argv[2]))
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
