#!/usr/bin/env python3
"""Verify bilingual resource coverage and interpolation before publishing."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "Sources/AlertCalendar"

def end_expr(s,i):
    level=1
    while i<len(s):
        if s[i]=='"': i=end_string(s,i);continue
        if s[i]=='(':level+=1
        if s[i]==')':
            level-=1
            if level==0:return i+1
        i+=1
    raise ValueError('Unclosed expression')
def end_string(s,i):
    q='"""' if s.startswith('"""',i) else '"';i+=len(q)
    while i<len(s):
        if s.startswith(q,i):return i+len(q)
        if s.startswith('\\(',i):i=end_expr(s,i+2);continue
        if s[i]=='\\':i+=2
        else:i+=1
    raise ValueError('Unclosed string')
def literals(s):
    i=0
    while i<len(s):
        if s.startswith('//',i):
            j=s.find('\n',i);i=j if j>=0 else len(s);continue
        if s.startswith('/*',i):
            j=s.find('*/',i+2);i=j+2 if j>=0 else len(s);continue
        if s[i]=='"':
            j=end_string(s,i)
            if not s.startswith('"""',i) and (i==0 or s[i-1]!='#'):yield i,j
            i=j;continue
        i+=1
def key_of(lit):
    s=lit[1:-1];out='';i=0
    while i<len(s):
        if s.startswith('\\(',i):out+='%@';i=end_expr(s,i+2);continue
        if s[i]=='\\' and i+1<len(s):
            out+= {'n':'\n','t':'\t','r':'\r','"':'"','\\':'\\'}.get(s[i+1],s[i+1]);i+=2
        else:out+=s[i];i+=1
    return out


def read_catalog(language):
    path = SOURCE_ROOT / "Resources/Localization" / f"{language}.lproj/Localizable.strings"
    result = {}
    for line in path.read_text().splitlines():
        match = re.fullmatch(r'("(?:[^"\\]|\\.)*") = ("(?:[^"\\]|\\.)*");', line)
        if not match:
            raise ValueError(f"Invalid catalog entry in {path}: {line}")
        key, value = (json.loads(part) for part in match.groups())
        if key in result:
            raise ValueError(f"Duplicate key: {key}")
        result[key] = value
    return result


def main():
    english = read_catalog("en")
    spanish = read_catalog("es-419")
    assert english.keys() == spanish.keys(), "Catalog keys differ"
    for key in english:
        assert english[key] == key, f"English fallback changed: {key}"
        assert spanish[key], f"Empty Spanish translation: {key}"
        assert key.count("%@") == spanish[key].count("%@"), f"Interpolation mismatch: {key}"
    uses = 0
    for source in SOURCE_ROOT.rglob("*.swift"):
        code = source.read_text()
        for start, end in literals(code):
            if re.search(r'L10n\.text\(\s*$', code[max(0, start - 50):start]):
                key = key_of(code[start:end])
                # Pure interpolation carries already formatted fragments.
                if re.search(r'[A-Za-z]', key.replace("%@", "")):
                    assert key in english, f"Missing translation in {source}: {key}"
                    uses += 1
    print(f"Localization checks passed: {len(english)} bilingual entries, {uses} source uses.")


if __name__ == "__main__":
    main()
