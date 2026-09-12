#!/usr/bin/env python3
"""Mechanical lint for a Markdown LLM wiki (raw layer + derived layer + INDEX).

Checks: broken relative links, orphan derived pages, derived pages missing from INDEX,
meeting files missing from meetings/README, frontmatter without `sources`,
`updated` older than the newest git change of its sources (stale *candidates*),
and relative-date words that rot overnight.
"""
import argparse, glob, os, re, subprocess

LINK = re.compile(r'\[[^\]]*\]\(([^)\s]+)\)')
RELATIVE_WORDS = ('明日', '来週', '今週', '翌日', '明後日')


def md_files(root, skip):
    for f in sorted(glob.glob(os.path.join(root, '**', '*.md'), recursive=True)):
        rel = os.path.relpath(f, root)
        if any(rel.startswith(s) or f'/{s}' in rel for s in skip):
            continue
        yield rel


def git_date(root, path):
    try:
        return subprocess.check_output(
            ['git', '-C', root, 'log', '-1', '--format=%ad', '--date=short', '--', path],
            text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ''


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', default='.')
    ap.add_argument('--derived', default='wiki', help='derived layer dir')
    ap.add_argument('--derived-subdirs', default='entities,concepts,analyses,decisions')
    ap.add_argument('--raw', default='career,meetings,projects', help='raw dirs (comma)')
    ap.add_argument('--index', default='wiki/INDEX.md')
    ap.add_argument('--meetings', default='meetings')
    ap.add_argument('--skip', default='.venv,node_modules,App', help='path fragments to skip')
    ap.add_argument('--ignore-link', action='append', default=[], help='link substrings to ignore')
    a = ap.parse_args()
    root = os.path.abspath(a.root)
    skip = a.skip.split(',')
    files = list(md_files(root, skip))

    print('===== BROKEN LINKS =====')
    for f in files:
        txt = open(os.path.join(root, f), encoding='utf-8').read()
        for m in LINK.finditer(txt):
            link = m.group(1)
            if link.startswith(('http://', 'https://', 'mailto:', '#')):
                continue
            target = link.split('#')[0]
            if not target or any(s in link for s in a.ignore_link):
                continue
            p = os.path.normpath(os.path.join(root, os.path.dirname(f), target))
            if not os.path.exists(p):
                print(f'{f}: {link}')

    derived = [f for f in files if f.startswith(a.derived + '/')
               and f.split('/')[1] in a.derived_subdirs.split(',')
               and not f.endswith('README.md')]
    corpus = {f: open(os.path.join(root, f), encoding='utf-8').read() for f in files}
    index_txt = corpus.get(a.index, '')

    print('===== ORPHANS / NOT IN INDEX =====')
    for f in derived:
        b = os.path.basename(f)
        if not any(b in t for g, t in corpus.items() if g != f):
            print(f'orphan: {f}')
        if b not in index_txt:
            print(f'not in INDEX: {f}')

    print('===== MEETINGS NOT IN README =====')
    readme = corpus.get(f'{a.meetings}/README.md', '')
    for f in files:
        if f.startswith(a.meetings + '/') and re.match(r'\d{4}-\d{2}-\d{2}-', os.path.basename(f)):
            if os.path.basename(f) not in readme:
                print(f'not in README: {f}')

    print('===== FRONTMATTER (no sources / stale candidates) =====')
    for f in derived + [f'{a.derived}/overview.md']:
        if f not in corpus:
            continue
        m = re.search(r'^---\n(.*?)\n---', corpus[f], re.S)
        if not m:
            print(f'NO FRONTMATTER: {f}')
            continue
        fm = m.group(1)
        if 'sources' not in fm and '/decisions/' not in f:
            print(f'NO SOURCES: {f}')
        upd = re.search(r'^updated:\s*(\S+)', fm, re.M)
        newest = ''
        for s in re.findall(r'^\s*-\s*(\.\./\S+)', fm, re.M):
            p = os.path.normpath(os.path.join(root, os.path.dirname(f), s))
            rel = os.path.relpath(p, root)
            if os.path.isdir(p):
                d = max((git_date(root, x) for x in glob.glob(p + '/*.md')), default='')
            else:
                d = git_date(root, rel)
            newest = max(newest, d)
        if upd and newest and newest > upd.group(1):
            print(f'STALE?: {f} updated={upd.group(1)} newest_source={newest}')

    print('===== RELATIVE DATES (rot overnight) =====')
    for f in files:
        if not (f.startswith(a.derived + '/') or f.startswith('career/interview/')):
            continue
        if f.endswith(('LOG.md', 'SCHEMA.md', 'conventions.md')) or '/templates/' in f:
            continue
        for i, line in enumerate(corpus[f].splitlines(), 1):
            if any(w in line for w in RELATIVE_WORDS) and '相対日付' not in line:
                print(f'{f}:{i}: {line.strip()[:80]}')


if __name__ == '__main__':
    main()
