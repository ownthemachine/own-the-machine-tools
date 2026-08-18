#!/usr/bin/env python3
"""Mechanical checks for the legislation pipeline. Free, fast, no excuses.

Checks regulation/ (and optionally any file passed as argv):
  1. no normative language in recitals (shall/must/is required to)
  2. no aspirational language in enacting terms (should/will endeavour)
  3. no em-dashes anywhere in the repo's prose
  4. cross-references "Article N" resolve to an existing article file
  5. defined-term discipline once regulation/articles/ has a definitions
     article: capitalised multiword terms used in articles must be defined

Exit 1 on any error; warnings do not fail the build.
Tolerant of the repo's current, mostly empty, state by design.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
REG = ROOT / "regulation"
errors: list[str] = []
warnings: list[str] = []

targets = [pathlib.Path(a) for a in sys.argv[1:]] or list(ROOT.rglob("*.md"))
targets = [t for t in targets if t.is_file() and ".git" not in t.parts]

NORMATIVE = re.compile(r"\b(shall|must|is required to|are required to)\b", re.I)
ASPIRATIONAL = re.compile(r"\b(should|will endeavour|strives? to|aims? to)\b", re.I)

for f in targets:
    text = f.read_text(encoding="utf-8")
    rel = f.relative_to(ROOT)
    for i, line in enumerate(text.splitlines(), 1):
        if "—" in line:
            errors.append(f"{rel}:{i}  em-dash")
        parts = f.parts
        if "recitals" in parts and NORMATIVE.search(line):
            errors.append(f"{rel}:{i}  normative language in a recital: {line.strip()[:70]}")
        if "articles" in parts and ASPIRATIONAL.search(line):
            errors.append(f"{rel}:{i}  aspirational language in enacting terms: {line.strip()[:70]}")

# cross-reference resolution, once articles exist
art_dir = REG / "articles"
if art_dir.exists():
    nums = set()
    for f in art_dir.glob("*.md"):
        m = re.match(r"(\d+)", f.stem)
        if m:
            nums.add(int(m.group(1)))
    if nums:
        for f in targets:
            if REG not in f.parents:
                continue
            for i, line in enumerate(f.read_text().splitlines(), 1):
                for m in re.finditer(r"Article (\d+)", line):
                    if int(m.group(1)) not in nums:
                        errors.append(
                            f"{f.relative_to(ROOT)}:{i}  dangling reference to Article {m.group(1)}"
                        )

# defined-term discipline, once a definitions article exists
defs_files = list(art_dir.glob("*definitions*.md")) if art_dir.exists() else []
if defs_files:
    defined = set(re.findall(r"'([^']{3,60})'\s+means", defs_files[0].read_text()))
    if defined:
        for f in art_dir.glob("*.md"):
            if f in defs_files:
                continue
            body = f.read_text()
            for term in re.findall(r"\b([A-Z][a-z]+ [A-Z][a-z]+(?: [A-Z][a-z]+)?)\b", body):
                if term not in defined and term not in {"Member State", "Member States", "Single Market", "European Union", "European Commission", "European Parliament"}:
                    warnings.append(f"{f.relative_to(ROOT)}  capitalised term not in definitions: {term}")

for w in sorted(set(warnings)):
    print(f"warn  {w}")
for e in errors:
    print(f"ERROR {e}")
print(f"\n{len(errors)} error(s), {len(set(warnings))} warning(s) across {len(targets)} file(s)")
sys.exit(1 if errors else 0)
