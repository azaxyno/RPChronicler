"""Rough Lua 5.1 checker: max active locals in the MAIN chunk and per function."""
import re, sys
src = open(sys.argv[1], encoding='utf-8').read()
tok_re = re.compile(r'''
 (?P<lcomment>--\[(?P<eq1>=*)\[.*?\](?P=eq1)\]) |
 (?P<comment>--[^\n]*) |
 (?P<lstr>\[(?P<eq2>=*)\[.*?\](?P=eq2)\]) |
 (?P<str>"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*') |
 (?P<name>[A-Za-z_][A-Za-z_0-9]*) |
 (?P<num>\d[\w.]*) |
 (?P<nl>\n) |
 (?P<op>\.\.\.|\.\.|==|~=|<=|>=|[^\s\w])
''', re.S | re.X)
toks = []
line = 1
for m in tok_re.finditer(src):
    k = m.lastgroup
    t = m.group(0)
    if k in ('lcomment', 'comment', 'lstr', 'str', 'num'):
        if k != 'comment' and k != 'lcomment':
            toks.append(('v', t, line))
        line += t.count('\n')
        continue
    if k == 'nl':
        line += 1
        continue
    toks.append((k, t, line))

frames = [{'blocks': [0], 'max': 0, 'maxline': 0, 'start': 1}]
results = []
pending_do = 0


def active(f):
    return sum(f['blocks'])


def add(n, ln):
    f = frames[-1]
    f['blocks'][-1] += n
    if active(f) > f['max']:
        f['max'] = active(f)
        f['maxline'] = ln


def open_function(i, ln, is_method):
    frames.append({'blocks': [0], 'max': 0, 'maxline': 0, 'start': ln})
    j = i
    while toks[j][1] != '(':
        j += 1
    j += 1
    n = 1 if is_method else 0
    while toks[j][1] != ')':
        if toks[j][0] == 'name' or toks[j][1] == '...':
            n += 1
        j += 1
    add(n, ln)
    return j + 1


i = 0
while i < len(toks):
    k, t, ln = toks[i]
    if k != 'name':
        i += 1
        continue
    if t == 'local':
        if toks[i + 1][1] == 'function':
            add(1, ln)
            i = open_function(i + 2, ln, False)
            continue
        j = i + 1
        n = 0
        while True:
            if toks[j][0] == 'name':
                n += 1
            j += 1
            if toks[j][1] == ',':
                j += 1
                continue
            break
        add(n, ln)
        i = j
        continue
    if t == 'function':
        j = i
        while toks[j][1] != '(':
            j += 1
        is_method = any(toks[x][1] == ':' for x in range(i, j))
        i = open_function(i, ln, is_method)
        continue
    if t == 'while':
        frames[-1]['blocks'].append(0)
        pending_do += 1
    elif t == 'for':
        frames[-1]['blocks'].append(0)
        pending_do += 1
        j = i + 1
        names = 0
        while toks[j][1] not in ('=', 'in'):
            if toks[j][0] == 'name':
                names += 1
            j += 1
        add(3 + names, ln)
        i = j
        continue
    elif t == 'do':
        if pending_do:
            pending_do -= 1
        else:
            frames[-1]['blocks'].append(0)
    elif t in ('if', 'repeat'):
        frames[-1]['blocks'].append(0)
    elif t in ('elseif', 'else'):
        frames[-1]['blocks'][-1] = 0
    elif t in ('end', 'until'):
        f = frames[-1]
        if len(f['blocks']) > 1:
            f['blocks'].pop()
        else:
            results.append(frames.pop())
    i += 1

main = frames[0]
print("%s: MAIN chunk max active locals %d (line %d), open frames at EOF %d"
      % (sys.argv[1], main['max'], main['maxline'], len(frames)))
for f in sorted(results, key=lambda f: -f['max'])[:2]:
    print("  function at line %d: max %d locals" % (f['start'], f['max']))
