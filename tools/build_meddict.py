#!/usr/bin/env python3
"""Build the app's offline medical dictionary from NLM MeSH.

Usage: build_meddict.py desc.xml.gz supp.xml.gz out.sqlite

- Descriptors (~30k): drugs, diseases, anatomy, processes, with scope-note definitions.
- Supplementary records: only drugs/chemicals that have a pharmacological action,
  so newer drugs (often not full descriptors) are covered too.

Source: MeSH, courtesy of the U.S. National Library of Medicine.
"""
import gzip
import sqlite3
import sys
import xml.etree.ElementTree as ET

CATEGORIES = {
    "A": "Anatomy", "B": "Organism", "C": "Disease", "D": "Drug / chemical",
    "E": "Technique / equipment", "F": "Psychiatry / psychology", "G": "Biological process",
    "H": "Discipline", "I": "Social science", "J": "Technology / industry",
    "K": "Humanities", "L": "Information science", "M": "Population group",
    "N": "Health care", "V": "Publication type", "Z": "Geography",
}


def text(el, path):
    found = el.find(path)
    return " ".join(found.text.split()) if found is not None and found.text else ""


def actions_of(rec):
    return [text(pa, "DescriptorReferredTo/DescriptorName/String")
            for pa in rec.findall("PharmacologicalActionList/PharmacologicalAction")]


def terms_of(rec):
    seen, out = set(), []
    for t in rec.findall("ConceptList/Concept/TermList/Term/String"):
        if t.text:
            s = " ".join(t.text.split())
            if s.lower() not in seen:
                seen.add(s.lower())
                out.append(s)
    return out


def records(path, tag):
    with gzip.open(path, "rb") as f:
        for _, el in ET.iterparse(f, events=("end",)):
            if el.tag == tag:
                yield el
                el.clear()


def main(desc_path, supp_path, out_path):
    db = sqlite3.connect(out_path)
    db.executescript("""
        PRAGMA journal_mode=OFF;
        DROP TABLE IF EXISTS entries; DROP TABLE IF EXISTS terms;
        CREATE TABLE entries(id INTEGER PRIMARY KEY, name TEXT, category TEXT,
                             definition TEXT, actions TEXT, synonyms TEXT);
        CREATE TABLE terms(term TEXT NOT NULL, entry_id INTEGER NOT NULL);
    """)
    next_id = 1
    term_rows = []

    def add(name, category, definition, actions, terms):
        nonlocal next_id
        synonyms = [t for t in terms if t.lower() != name.lower()][:12]
        db.execute("INSERT INTO entries VALUES (?,?,?,?,?,?)",
                   (next_id, name, category, definition, "; ".join(a for a in actions if a), "; ".join(synonyms)))
        for t in {name.lower(), *[x.lower() for x in terms]}:
            term_rows.append((t, next_id))
        next_id += 1

    n_desc = 0
    for rec in records(desc_path, "DescriptorRecord"):
        name = text(rec, "DescriptorName/String")
        trees = [t.text for t in rec.findall("TreeNumberList/TreeNumber") if t.text]
        category = CATEGORIES.get(trees[0][0], "") if trees else ""
        note = text(rec, "ConceptList/Concept[@PreferredConceptYN='Y']/ScopeNote")
        if not name or not note:
            continue
        add(name, category, note, actions_of(rec), terms_of(rec))
        n_desc += 1

    n_supp = 0
    for rec in records(supp_path, "SupplementalRecord"):
        acts = actions_of(rec)
        if not acts:
            continue
        name = text(rec, "SupplementalRecordName/String")
        note = text(rec, "Note")
        mapped = [text(h, "DescriptorReferredTo/DescriptorName/String").lstrip("*")
                  for h in rec.findall("HeadingMappedToList/HeadingMappedTo")]
        if not note:
            note = "Related to: " + ", ".join(m for m in mapped if m) if mapped else ""
        if not name or not note:
            continue
        add(name, "Drug / chemical", note, acts, terms_of(rec))
        n_supp += 1

    db.executemany("INSERT INTO terms VALUES (?,?)", term_rows)
    db.execute("CREATE INDEX terms_term ON terms(term)")
    db.commit()
    db.execute("VACUUM")
    db.close()
    print(f"descriptors={n_desc} drugs_from_supplementary={n_supp} terms={len(term_rows)}")


if __name__ == "__main__":
    main(*sys.argv[1:4])
