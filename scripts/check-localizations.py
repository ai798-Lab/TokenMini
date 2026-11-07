#!/usr/bin/env python3
"""Validate bundled UI translations and interpolation contracts without network access."""
import re,json,pathlib,sys
root=pathlib.Path(__file__).resolve().parents[1]
def string_end(s,i):
    j=i+1
    while j<len(s):
        if s.startswith('\\(',j):
            j=expr_end(s,j+2)+1; continue
        if s[j]=='\\':j+=2;continue
        if s[j]=='"':return j+1
        j+=1
    raise ValueError(s[i:i+100])
def expr_end(s,j):
    depth=1
    while j<len(s):
        if s[j]=='"':j=string_end(s,j);continue
        if s[j]=='(':depth+=1
        if s[j]==')':
            depth-=1
            if depth==0:return j
        j+=1
    raise ValueError('expression')
def tokens(s):
    i=0
    while i<len(s):
        if s.startswith('//',i):
            i=s.find('\n',i)
            if i<0:return
        elif s.startswith('/*',i):
            e=s.find('*/',i+2);i=len(s) if e<0 else e+2
        elif s.startswith('"""',i):
            e=s.find('"""',i+3);i=len(s) if e<0 else e+3
        elif s[i]=='"':
            e=string_end(s,i);yield i,e,s[i:e];i=e
        else:i+=1

def key(raw):
    s=raw[1:-1];j=0;out='';n=0
    while j<len(s):
        if s.startswith('\\(',j):
            e=expr_end(s,j+2);out+='{'+str(n)+'}';n+=1;j=e+1
        elif s[j]=='\\' and j+1<len(s):
            out+={'n':'\n','t':'\t','r':'\r','"':'"','\\':'\\','0':'\0'}.get(s[j+1],s[j:j+2]);j+=2
        else:out+=s[j];j+=1
    return out

langs=['en','zh-Hant','ja','ko','ar']
entries=json.loads((root/'Sources/MacPulse/Localization/Translations.json').read_text())
errors=[]
pattern=re.compile(r'\{[0-9]+\}|%(?:[0-9]+\$)?[-+0#]*(?:[0-9]+)?(?:\.[0-9]+)?(?:ll|l|z)?[diuoxXfFeEgGcs@%]')
for source,translations in entries.items():
    for lang in langs:
        value=translations.get(lang)
        if not value:errors.append(f'{lang}: missing {source}')
        elif sorted(pattern.findall(source))!=sorted(pattern.findall(value)):errors.append(f'{lang}: placeholder mismatch: {source}')
used=set()
for p in (root/'Sources/MacPulse').rglob('*.swift'):
    if 'Localization' in p.parts:continue
    s=p.read_text()
    for a,b,raw in tokens(s):
        if re.search(r'L10n\.(?:text|lookup)\(\s*$',s[max(0,a-40):a]):
            k=key(raw);used.add(k)
            if k not in entries:errors.append(f'{p.relative_to(root)}:{s.count(chr(10),0,a)+1}: missing key {k}')
if errors:
    print('\n'.join(errors));sys.exit(1)
print(f'PASS: {len(entries)} keys x {len(langs)} translations; {len(used)} referenced literal keys; placeholder parity verified.')
