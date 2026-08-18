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

ROOT = pathlib.Path.cwd()  # run from the repo root under review
REG = ROOT / "regulation"
errors: list[str] = []
warnings: list[str] = []

targets = [pathlib.Path(a) for a in sys.argv[1:]] or list(ROOT.rglob("*.md"))
targets = [t for t in targets if t.is_file() and ".git" not in t.parts]

NORMATIVE = re.compile(r"\b(shall|must|is required to|are required to)\b", re.I)
ASPIRATIONAL = re.compile(r"\b(should|will endeavour|strives? to|aims? to)\b", re.I)

EXTERNAL = re.compile(r"TFEU|TEU\b|Charter|Directive|Regulation \(|Recommendation|Decision|Act of|thereof|of that (Directive|Regulation)")

def legal_part(f, text):
    """Drafting notes after a bare '---' line are non-normative; content
    checks stop there. The em-dash check still covers the whole file."""
    if "articles" in f.parts and "\n---\n" in text:
        return text.split("\n---\n")[0]
    return text

def is_external_ref(line, m):
    if int(m.group(1)) > 40:      # no internal article number runs that high
        return True
    ctx = line[max(0, m.start() - 70):m.start()] + " | " + line[m.end():m.end() + 45]
    return bool(EXTERNAL.search(ctx))

for f in targets:
    try:
        text = f.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        warnings.append(f"{f.relative_to(ROOT)}  not valid UTF-8, skipped")
        continue
    rel = f.relative_to(ROOT)
    body = legal_part(f, text)
    for i, line in enumerate(text.splitlines(), 1):
        if "—" in line:
            errors.append(f"{rel}:{i}  em-dash")
    for i, line in enumerate(body.splitlines(), 1):
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
            txt = f.read_text(errors="replace")
            for i, line in enumerate(legal_part(f, txt).splitlines(), 1):
                for m in re.finditer(r"Article (\d+)", line):
                    if int(m.group(1)) not in nums and not is_external_ref(line, m):
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
            body = legal_part(f, f.read_text(errors="replace"))
            for term in re.findall(r"(?<![.!?]\s)\b([A-Z][a-z]+ [A-Z][a-z]+(?: [A-Z][a-z]+)?)\b", body):
                if term not in defined and term not in {"Member State", "Member States", "Single Market", "European Union", "European Commission", "European Parliament", "This Regulation", "The Commission", "The Reserve", "European Citizens", "Capital Reserve", "Fundamental Rights", "Annex I", "Charter of Fundamental Rights"}:
                    warnings.append(f"{f.relative_to(ROOT)}  capitalised term not in definitions: {term}")

for w in sorted(set(warnings)):
    print(f"warn  {w}")
for e in errors:
    print(f"ERROR {e}")
print(f"\n{len(errors)} error(s), {len(set(warnings))} warning(s) across {len(targets)} file(s)")
sys.exit(1 if errors else 0)
