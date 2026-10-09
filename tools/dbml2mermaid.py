"""Convert docs/schema.dbml into a Mermaid ER diagram (docs/er-diagram.md).

GitHub renders Mermaid natively, so the diagram is visible right in the repo.
Supports the DBML subset used in this project: Table blocks, column settings
(pk, unique, not null, inline `ref: >`), composite `indexes { (...) [pk] }`
and standalone `Ref:` lines.

Usage: python tools/dbml2mermaid.py
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "docs" / "schema.dbml"
DST = ROOT / "docs" / "er-diagram.md"

TABLE_RE = re.compile(r"^Table\s+(\w+)\s*\{")
COL_RE = re.compile(r"^(\w+)\s+([\w(),]+)\s*(?:\[(.*)\])?\s*$")
INLINE_REF_RE = re.compile(r"ref:\s*([<>-])\s*(\w+)\.(\w+)")
STANDALONE_REF_RE = re.compile(r"^Ref:\s*(\w+)\.(\w+)\s*([<>-])\s*(\w+)\.(\w+)")
COMPOSITE_PK_RE = re.compile(r"^\(([\w,\s]+)\)\s*\[.*\bpk\b.*\]")
NOTE_RE = re.compile(r"note:\s*'([^']*)'")


def parse(text):
    tables, refs = {}, []
    current, in_indexes = None, False
    for raw in text.splitlines():
        line = raw.split("//")[0].strip()
        if not line:
            continue
        if m := TABLE_RE.match(line):
            current = m.group(1)
            tables[current] = []
            continue
        if m := STANDALONE_REF_RE.match(line):
            refs.append((m.group(1), m.group(2), m.group(3), m.group(4), m.group(5)))
            continue
        if current is None:
            continue
        if line.startswith("indexes"):
            in_indexes = True
            continue
        if line == "}":
            if in_indexes:
                in_indexes = False
            else:
                current = None
            continue
        if in_indexes:
            if m := COMPOSITE_PK_RE.match(line):
                for name in (c.strip() for c in m.group(1).split(",")):
                    for col in tables[current]:
                        if col["name"] == name:
                            col["pk"] = True
            continue
        if m := COL_RE.match(line):
            name, typ, settings = m.group(1), m.group(2), m.group(3) or ""
            col = {
                "name": name,
                "type": re.sub(r"\(.*\)", "", typ),
                "pk": bool(re.search(r"\bpk\b", settings)),
                "uk": bool(re.search(r"\bunique\b", settings)),
                "not_null": "not null" in settings or "pk" in settings,
                "fk": False,
                "note": "",
            }
            if n := NOTE_RE.search(settings):
                col["note"] = n.group(1).replace('"', "'")
            if r := INLINE_REF_RE.search(settings):
                col["fk"] = True
                refs.append((current, name, r.group(1), r.group(2), r.group(3)))
            tables[current].append(col)
    # mark FK columns that came from standalone refs
    for t, c, *_ in refs:
        for col in tables.get(t, []):
            if col["name"] == c:
                col["fk"] = True
    return tables, refs


def render(tables, refs):
    out = ["erDiagram"]
    for t, c, kind, pt, pc in refs:
        nullable = not next(col for col in tables[t] if col["name"] == c)["not_null"]
        parent_card = "|o" if nullable else "||"
        child_card = "o|" if kind == "-" else "o{"
        out.append(f'    {pt} {parent_card}--{child_card} {t} : "{c}"')
    for t, cols in tables.items():
        out.append(f"    {t} {{")
        for col in cols:
            keys = [k for k, on in (("PK", col["pk"]), ("FK", col["fk"]), ("UK", col["uk"])) if on]
            line = f"        {col['type']} {col['name']}"
            if keys:
                line += " " + ",".join(keys)
            if col["note"]:
                line += f' "{col["note"]}"'
            out.append(line)
        out.append("    }")
    return "\n".join(out)


def main():
    tables, refs = parse(SRC.read_text(encoding="utf-8"))
    body = render(tables, refs)
    DST.write_text(
        "# ER diagram\n\n"
        "> Generated from [`schema.dbml`](schema.dbml) by `python tools/dbml2mermaid.py`.\n"
        "> The same DBML can be pasted into <https://dbdiagram.io/d> for an interactive view.\n\n"
        f"Entities: **{len(tables)}**, relationships: **{len(refs)}**.\n\n"
        "```mermaid\n" + body + "\n```\n",
        encoding="utf-8",
    )
    print(f"{len(tables)} tables, {len(refs)} refs -> {DST.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
