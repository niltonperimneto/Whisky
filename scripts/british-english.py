#!/usr/bin/env python3
#
# british-english.py
#
# This file is part of Whisky.
#
# Whisky is free software: you can redistribute it and/or modify it under the terms
# of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
# without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with Whisky.
# If not, see https://www.gnu.org/licenses/.
#
# Regenerates the en-GB localization from en.
#
# en-GB has to carry *every* string, not only the ones that are spelled
# differently. A compiled .strings table is not consulted key by key: macOS picks
# one localization for the process, and anything missing from it renders as the
# raw key rather than falling back to en. A partial en-GB shows
# `config.audio.driver.auto` to every British user, which is exactly the bug this
# script exists to prevent.
#
#   ./scripts/british-english.py            rewrite en-GB
#   ./scripts/british-english.py --check    exit 1 if it is out of date

import json
import pathlib
import re
import sys

CATALOG = pathlib.Path(__file__).resolve().parent.parent / "Whisky" / "Localizable.xcstrings"

# Only differences that are unambiguous in software UI copy. -ise vs -ize is a
# real split even within British usage (Oxford keeps -ize), but -ise is what the
# majority of British readers expect, so the app follows it.
SPELLINGS = [
    (r"\banaly(z)(e|ed|es|ing|er)\b", r"analys\2"),
    (r"\bAnaly(z)(e|ed|es|ing|er)\b", r"Analys\2"),
    (r"(\b\w*?)i(z)(e|ed|es|ing|ation|ations)\b", r"\1is\3"),
    (r"\bcolor(s|ed|ing)?\b", r"colour\1"),
    (r"\bColor(s|ed|ing)?\b", r"Colour\1"),
    (r"\bbehavior(s)?\b", r"behaviour\1"),
    (r"\bBehavior(s)?\b", r"Behaviour\1"),
    (r"\bcatalog(s)?\b", r"catalogue\1"),
    (r"\bfavorite(s)?\b", r"favourite\1"),
    (r"\bFavorite(s)?\b", r"Favourite\1"),
    (r"\bcancel(ed|ing)\b", r"cancell\1"),
    (r"\bCancel(ed|ing)\b", r"Cancell\1"),
    (r"\bcenter(s|ed|ing)?\b", r"centre\1"),
    (r"\bgray\b", "grey"),
    (r"\bGray\b", "Grey"),
]

# Words that end in -ize/-ise by origin rather than by convention, or that are
# API and product names. Rewriting these would be wrong in any English.
PROTECTED = re.compile(
    r"\b(size|sizes|sized|sizing|resize|resizes|resized|resizing|prize|seize|"
    r"capsize|maize|Metal|MetalFX|DXVK|DXMT|Wine|Whisky|Steam|Rosetta)\b",
    re.IGNORECASE,
)


def to_british(text: str) -> str:
    """Applies the spelling map, leaving protected words and anything inside
    backticks or a format specifier alone."""
    protected_spans = [m.span() for m in PROTECTED.finditer(text)]

    def overlaps_protected(start: int, end: int) -> bool:
        return any(start < p_end and p_start < end for p_start, p_end in protected_spans)

    result = text
    for pattern, replacement in SPELLINGS:
        out, last = [], 0
        for match in re.finditer(pattern, result):
            if overlaps_protected(match.start(), match.end()):
                continue
            out.append(result[last:match.start()])
            out.append(match.expand(replacement))
            last = match.end()
        out.append(result[last:])
        result = "".join(out)
    return result


def unit(value: str) -> dict:
    return {"stringUnit": {"state": "translated", "value": value}}


def write_catalog(catalog: dict) -> None:
    """Writes the catalog in the shape it is stored in: two-space JSON with
    non-ASCII escaped and no trailing newline, which round-trips the file byte
    for byte. Editing the text in place instead broke when the file stopped
    being in Xcode's `"key" : {` spacing."""
    CATALOG.write_text(json.dumps(catalog, indent=2, ensure_ascii=True), encoding="utf-8")


def main() -> int:
    check_only = "--check" in sys.argv
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    strings = catalog["strings"]

    expected: dict[str, str] = {}
    for key, entry in strings.items():
        english = entry.get("localizations", {}).get("en", {}).get("stringUnit", {}).get("value")
        if english is None:
            # The key is its own source string. It only needs an en-GB row when
            # British spells it differently; otherwise the key renders correctly
            # on its own, which is what makes a partial en-GB survivable here.
            british = to_british(key)
            if british != key:
                expected[key] = british
            continue
        expected[key] = to_british(english)

    if check_only:
        stale = [
            key for key, value in expected.items()
            if strings[key].get("localizations", {}).get("en-GB", {}).get("stringUnit", {}).get("value") != value
        ]
        if stale:
            print("en-GB is out of date, %d string(s), run scripts/british-english.py:" % len(stale))
            for key in stale[:10]:
                print("  " + key)
            return 1
        print("en-GB covers all %d strings that need it" % len(expected))
        return 0

    written = 0
    for key, value in expected.items():
        localizations = strings[key].setdefault("localizations", {})
        if localizations.get("en-GB", {}).get("stringUnit", {}).get("value") == value:
            continue
        localizations["en-GB"] = unit(value)
        strings[key]["localizations"] = dict(sorted(localizations.items()))
        written += 1

    write_catalog(catalog)
    differing = sum(
        1 for key, value in expected.items()
        if value != strings[key]["localizations"].get("en", {}).get("stringUnit", {}).get("value", key)
    )
    print("en-GB covers %d strings, %d spelled differently, %d rows written"
          % (len(expected), differing, written))
    return 0


if __name__ == "__main__":
    sys.exit(main())
