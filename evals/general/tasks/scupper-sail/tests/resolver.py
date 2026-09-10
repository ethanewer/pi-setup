#!/usr/bin/env python3
"""Verifier engine for scupper-sail.

Parses the agent's stylesheet with tinycss2, resolves the cascade for each
hidden viewport fixture (media layers, container layers, specificity, custom
property inheritance and var() substitution), checks the dashboard HTML
vocabulary, and asserts the media-query structure and the custom properties
named by the contract. Writes nothing itself; the caller (test.sh) owns the
reward file. Prints a readable failure list before the caller writes 0.

Run: python3 /tests/resolver.py <styles.css> <dashboard.html> <hidden_dir>
"""
import json
import os
import re
import sys
from html.parser import HTMLParser

import tinycss2

failures = []


def fail(msg):
    failures.append(msg)


def norm(s):
    s = re.sub(r'\s+', ' ', s).strip().lower()
    s = re.sub(r'\s*([(),:;/-])\s*', r'\1', s)
    return s


VAR_RE = re.compile(r'var\((--[a-zA-Z0-9_-]+)(?:\s*,\s*([^)]*))?\)')


def resolve_vars(value, props, depth=0):
    if depth > 12 or 'var(' not in value:
        return value

    def repl(m):
        name = m.group(1)
        if name in props:
            return props[name]
        if m.group(2) is not None:
            return m.group(2)
        return m.group(0)

    out = VAR_RE.sub(repl, value)
    if out == value:
        return value
    return resolve_vars(out, props, depth + 1)


# --------------------------------------------------------------------------
# DOM
# --------------------------------------------------------------------------

class Node:
    def __init__(self, tag, classes, nid, width, children, parent=None):
        self.tag = tag
        self.classes = classes
        self.nid = nid
        self.width = width
        self.children = children
        self.parent = parent

    def dom_id(self):
        if self.nid:
            return '#' + self.nid
        return '.' + '.'.join(self.classes) if self.classes else self.tag


def build_dom(d, parent=None):
    n = Node(d.get('tag', 'div'), (d.get('class') or '').split(),
             d.get('id'), d.get('width'), [], parent)
    for c in d.get('children', []):
        n.children.append(build_dom(c, n))
    return n


def all_nodes(n):
    yield n
    for c in n.children:
        yield from all_nodes(c)


# --------------------------------------------------------------------------
# Selectors
# --------------------------------------------------------------------------

def token_match(sel, pos, pattern):
    m = re.match(pattern, sel[pos:])
    return m


def parse_simple(sel):
    """One simple selector: optional type, #id, :root, and .classes in the
    documented vocabulary. Returns a dict, or None outside the subset."""
    ids, classes, pseudo, types = [], [], [], []
    i = 0
    m = token_match(sel, i, r'[a-zA-Z][\w-]*')
    if m:
        types.append(m.group(0).lower())
        i += m.end()
    while i < len(sel):
        ch = sel[i]
        if ch == ':':
            m2 = token_match(sel, i, r':root\b')
            if m2:
                pseudo.append('root')
                i += m2.end()
                continue
            return None
        if ch == '#':
            m2 = token_match(sel, i, r'#[a-zA-Z_][\w-]*')
            if m2 is None:
                return None
            ids.append(m2.group(0)[1:])
            i += m2.end()
            continue
        if ch == '.':
            m2 = token_match(sel, i, r'\.[a-zA-Z_][\w-]*')
            if m2 is None:
                return None
            classes.append(m2.group(0)[1:])
            i += m2.end()
            continue
        return None
    return {'ids': ids, 'classes': classes, 'pseudo': pseudo, 'types': types}


def split_compound(sel):
    """Split a compound selector into [(op, simple), ...]; op None for the
    first simple, '>' for child, ' ' for descendant."""
    parts = []
    cur = ''
    i = 0
    n = len(sel)
    while i < n:
        ch = sel[i]
        if ch.isspace() or ch == '>':
            if cur:
                parts.append((None, cur))
                cur = ''
            op = '>' if ch == '>' else ' '
            i += 1
            while i < n and (sel[i].isspace() or sel[i] == '>'):
                if sel[i] == '>' and op == ' ':
                    op = '>'
                i += 1
            parts.append((op, None))
            continue
        cur += ch
        i += 1
    if cur:
        parts.append((None, cur))
    if not parts or parts[0][0] is not None or parts[0][1] is None:
        return None
    out = []
    pending_op = None
    for op, s in parts:
        if s is None:
            pending_op = op
        else:
            out.append((pending_op, s))
            pending_op = None
    if len(out) != len([p for p in parts if p[1] is not None]):
        return None
    return out


class Selector:
    def __init__(self, text):
        self.text = norm(text)
        self.specificity = None
        parts = split_compound(self.text)
        self.ok = parts is not None
        if not self.ok:
            return
        self.simple = []
        for op, s in parts:
            ps = parse_simple(s)
            if ps is None:
                self.ok = False
                return
            self.simple.append((op, ps))
        ids = sum(len(ps['ids']) for _, ps in self.simple)
        classes = sum(len(ps['classes']) for _, ps in self.simple) \
            + sum(len(ps['pseudo']) for _, ps in self.simple)
        types = sum(len(ps['types']) for _, ps in self.simple)
        self.specificity = (ids, classes, types)

    def matches(self, node, is_root):
        def simple_matches(ps, n2):
            if 'root' in ps['pseudo']:
                if not is_root(n2):
                    return False
            for t in ps['types']:
                if n2.tag != t:
                    return False
            if ps['ids'] and n2.nid not in ps['ids']:
                return False
            for cl in ps['classes']:
                if cl not in n2.classes:
                    return False
            return True

        idx = len(self.simple) - 1
        cur = node
        if not simple_matches(self.simple[idx][1], cur):
            return False
        idx -= 1
        while idx >= 0:
            op, ps = self.simple[idx]
            if op == '>':
                cur = cur.parent
                if cur is None or not simple_matches(ps, cur):
                    return False
            else:
                anchor = None
                p = cur.parent
                while p is not None:
                    if simple_matches(ps, p):
                        anchor = p
                        break
                    p = p.parent
                if anchor is None:
                    return False
                cur = anchor
            idx -= 1
        return True


# --------------------------------------------------------------------------
# Stylesheet model
# --------------------------------------------------------------------------

COND_RE = re.compile(r'\((min-width|max-width)\s*:\s*([^()]+?)\)')


def parse_cond(prelude_str):
    pairs = []
    for m in COND_RE.finditer(norm(prelude_str)):
        pairs.append((m.group(1), norm(m.group(2))))
    return pairs


class Declaration:
    def __init__(self, name, value):
        self.name = name
        self.value = value


def make_declaration(d):
    """Property names are ASCII-case-insensitive in CSS; custom properties
    (--*) are case-sensitive. Normalize the former, leave the latter alone."""
    name = str(d.name)
    if not name.startswith('--'):
        name = name.lower()
    return Declaration(name, tinycss2.serialize(d.value))


class Rule:
    def __init__(self, selector, decls, idx):
        self.selector = selector
        self.decls = decls
        self.idx = idx


class Layer:
    def __init__(self, kind, cond, rules):
        self.kind = kind      # 'plain' | 'media' | 'container'
        self.cond = cond      # [(feature, value), ...]
        self.rules = rules


def num_px(value):
    m = re.fullmatch(r'([0-9.]+)px', value)
    return float(m.group(1)) if m else None


def parse_stylesheet(css_text):
    """Returns (layers, errors, all_decls).
    Constructs outside the documented subset (other at-rules, exotic
    selectors) are reported as warnings and skipped; the structural and
    behavioral assertions carry the pass/fail verdict."""
    errors = []
    warnings = []
    layers = []
    all_decls = []

    def parse_rules(tokens, where):
        out = []
        for r in tinycss2.parse_rule_list(
                tokens, skip_whitespace=True, skip_comments=True):
            if type(r).__name__ == 'ParseError':
                warnings.append('rule parse error in %s: %s'
                                % (where, r.message))
                continue
            sel = Selector(tinycss2.serialize(r.prelude))
            if not sel.ok:
                warnings.append('skipping unsupported selector in %s: %r'
                                % (where, tinycss2.serialize(r.prelude)))
                continue
            decls = []
            for d in tinycss2.parse_declaration_list(
                    r.content, skip_whitespace=True, skip_comments=True):
                if type(d).__name__ == 'ParseError':
                    warnings.append('declaration parse error inside %r: %s'
                                    % (sel.text, d.message))
                    continue
                decls.append(make_declaration(d))
            all_decls.extend(decls)
            out.append(Rule(sel, decls, None))
        return out

    top = tinycss2.parse_stylesheet(css_text, skip_whitespace=True,
                                    skip_comments=True)
    for item in top:
        tn = type(item).__name__
        if tn == 'ParseError':
            warnings.append('stylesheet parse error: %s' % item.message)
            continue
        if isinstance(item, tinycss2.ast.QualifiedRule):
            sel = Selector(tinycss2.serialize(item.prelude))
            if not sel.ok:
                warnings.append('skipping unsupported selector: %r'
                                % tinycss2.serialize(item.prelude))
                continue
            decls = []
            for d in tinycss2.parse_declaration_list(
                    item.content, skip_whitespace=True, skip_comments=True):
                if type(d).__name__ == 'ParseError':
                    warnings.append('declaration parse error: %s' % d.message)
                    continue
                decls.append(make_declaration(d))
            all_decls.extend(decls)
            layers.append(Layer('plain', None, [Rule(sel, decls, None)]))
        else:
            keyword = item.at_keyword.strip('@')
            if keyword not in ('media', 'container'):
                warnings.append('skipping unsupported at-rule @%s' % keyword)
                continue
            cond = parse_cond(tinycss2.serialize(item.prelude))
            rules = parse_rules(item.content, '@' + keyword)
            layers.append(Layer(keyword, cond, rules))

    idx = 0
    for layer in layers:
        for rule in layer.rules:
            rule.idx = idx
            idx += 1
    return layers, warnings, all_decls


# --------------------------------------------------------------------------
# Cascade resolution
# --------------------------------------------------------------------------

def media_active(cond, viewport):
    for feature, value in cond:
        n = num_px(value)
        if n is None:
            return False
        if feature == 'min-width' and not (viewport >= n):
            return False
        if feature == 'max-width' and not (viewport <= n):
            return False
    return True


def container_width(node, ctmap, viewport):
    p = node.parent
    while p is not None:
        if ctmap.get(id(p)) == 'inline-size':
            return p.width if p.width is not None else viewport
        p = p.parent
    return None


def resolved_props(node, is_root, sheet, viewport, ctmap):
    cands = {}
    for layer in sheet:
        if layer.kind == 'media' and not media_active(layer.cond, viewport):
            continue
        if layer.kind == 'container':
            if ctmap is None:
                continue
            w = container_width(node, ctmap, viewport)
            if w is None:
                continue
            ok = True
            for feature, value in layer.cond:
                n = num_px(value)
                if n is None or (feature == 'min-width' and not (w >= n)) \
                        or (feature == 'max-width' and not (w <= n)):
                    ok = False
                    break
            if not ok:
                continue
        for rule in layer.rules:
            if not rule.selector.matches(node, is_root):
                continue
            for d in rule.decls:
                cands.setdefault(d.name, []).append(
                    (rule.selector.specificity, rule.idx, d.value))
    resolved = {}
    for prop, lst in cands.items():
        lst.sort(key=lambda t: (t[0], t[1]))
        resolved[prop] = lst[-1][2]
    return resolved


# --------------------------------------------------------------------------
# Structural checks
# --------------------------------------------------------------------------

NAMED_PROPS = {
    '--scupper-grid-cols': '12',
    '--scupper-gap': '16px',
    '--scupper-bp-sm': '768px',
    '--scupper-bp-lg': '1280px',
    '--scupper-sidebar-span': '4',
    '--scupper-rail-span': '1',
    '--scupper-main-span-lg': '8',
    '--scupper-main-span-tablet': '11',
    '--scupper-main-span-mobile': '12',
    '--scupper-bg-sidebar': '#1e293b',
    '--scupper-bg-sidebar-open': '#0f172a',
    '--scupper-bg-main': '#f8fafc',
    '--scupper-bg-card': '#ffffff',
    '--scupper-bg-stat': '#e2e8f0',
}
BP_LIKE = {'--scupper-bp-sm', '--scupper-bp-lg'}

REQUIRED_MEDIA = [('min-width', '1280px'), ('max-width', '767px')]
# (class token, exact (min-width) condition, grid-column the block must
# resolve to). The declaration must live in the SAME block that carries the
# condition and target the class, so a stylesheet cannot satisfy the
# container-query contract with decoy blocks that never fire or fire at
# wrong thresholds while real behavior is keyed off the viewport.
REQUIRED_CONTAINER = [('.stat', '480px', 'span 2'),
                      ('.card', '720px', 'span 2'),
                      ('.card', '960px', 'span 3')]


def class_in_selector(selector_text, cls):
    """True if the class token (e.g. '.stat') occurs in the normalized
    selector text as a whole class name, not as a prefix of another
    identifier ('.stats' must not satisfy '.stat')."""
    return re.search(r'\.' + re.escape(cls[1:]) + r'(?![a-zA-Z0-9_-])',
                     selector_text) is not None


def structural_checks(sheet, all_decls):
    root_decls = {}
    for layer in sheet:
        if layer.kind != 'plain':
            continue
        for rule in layer.rules:
            if rule.selector.text == ':root':
                for d in rule.decls:
                    if d.name.startswith('--'):
                        root_decls[d.name] = norm(d.value)
    for name, value in NAMED_PROPS.items():
        got = root_decls.get(name)
        if got is None:
            fail('custom property %s not declared on :root' % name)
        elif got != norm(value):
            fail('custom property %s: got %r want %r' % (name, got, norm(value)))

    media_conds = [l.cond for l in sheet if l.kind == 'media']
    for feature, value in REQUIRED_MEDIA:
        if not any((feature, value) in conds for conds in media_conds):
            fail('no @media block with condition (%s: %s)' % (feature, value))

    container_blocks = [(l.cond, l.rules) for l in sheet
                        if l.kind == 'container']
    for cls, value, want in REQUIRED_CONTAINER:
        found = False
        for conds, rules in container_blocks:
            if ('min-width', value) not in conds:
                continue
            for rule in rules:
                if not class_in_selector(rule.selector.text, cls):
                    continue
                for d in rule.decls:
                    if d.name != 'grid-column':
                        continue
                    if resolve_vars(norm(d.value), root_decls) == want:
                        found = True
                        break
                if found:
                    break
            if found:
                break
        if not found:
            fail('no @container (min-width: %s) block targeting %s that '
                 'declares grid-column resolving to %s'
                 % (value, cls, want))

    all_text = ' '.join(d.value for d in all_decls)
    for name in NAMED_PROPS:
        if name in BP_LIKE:
            continue
        if ('var(' + name) not in all_text:
            fail('custom property %s is never consumed by var()' % name)

    base_spec = override_spec = None
    for layer in sheet:
        if layer.kind != 'plain':
            continue
        for rule in layer.rules:
            if rule.selector.text == '.sidebar':
                base_spec = rule.selector.specificity
            if rule.selector.text == '.sidebar.open':
                override_spec = rule.selector.specificity
    if base_spec is None:
        fail('no base rule with selector .sidebar')
    if override_spec is None:
        fail('no state rule with selector .sidebar.open')
    elif base_spec is not None and override_spec <= base_spec:
        fail('specificity of .sidebar.open %r must exceed .sidebar %r'
             % (override_spec, base_spec))


# --------------------------------------------------------------------------
# HTML vocabulary checks
# --------------------------------------------------------------------------

VOID_TAGS = {'meta', 'link', 'br', 'img', 'input', 'hr', 'wbr', 'source',
             'track', 'area', 'base', 'col', 'embed', 'param', 'keygen'}


class HtmlTree(HTMLParser):
    """Builds a small tree (tag, classes, id, attrs, children) from the
    dashboard page. tag names and attribute names are lowercased; void
    elements are recorded but not pushed on the stack; unbalanced markup is
    reported as errors."""

    def __init__(self):
        super().__init__()
        self.root = None
        self.stack = []
        self.errors = []

    def _attrs(self, attrs):
        return {k.lower(): (v or '').strip() for k, v in attrs}

    def _node(self, tag, a):
        return {'tag': tag.lower(),
                'classes': set((a.get('class') or '').split()),
                'id': a.get('id'),
                'attrs': a,
                'children': []}

    def _attach(self, node):
        if self.stack:
            self.stack[-1]['children'].append(node)
        else:
            if self.root is None:
                self.root = node

    def handle_starttag(self, tag, attrs):
        a = self._attrs(attrs)
        node = self._node(tag, a)
        self._attach(node)
        if tag.lower() not in VOID_TAGS:
            self.stack.append(node)

    def handle_startendtag(self, tag, attrs):
        self._attach(self._node(tag, self._attrs(attrs)))

    def handle_endtag(self, tag):
        t = tag.lower()
        if not self.stack:
            self.errors.append('closing </%s> with no open element' % t)
            return
        if self.stack[-1]['tag'] != t:
            self.errors.append(
                'tag closed out of order: </%s>, open elements: %s'
                % (t, ' > '.join(e['tag'] for e in self.stack)))
            for i in range(len(self.stack) - 1, -1, -1):
                if self.stack[i]['tag'] == t:
                    del self.stack[i:]
                    return
            return
        self.stack.pop()


def walk(node):
    if node is None:
        return
    yield node
    for c in node['children']:
        yield from walk(c)


def html_checks(path):
    try:
        text = open(path, encoding='utf-8', errors='replace').read()
    except OSError as e:
        fail('cannot read dashboard html: %s' % e)
        return
    if re.search(r'<!doctype\s+html', text, re.I) is None:
        fail('dashboard html: missing <!DOCTYPE html>')

    p = HtmlTree()
    try:
        p.feed(text)
        p.close()
    except Exception as e:
        fail('dashboard html: parse error: %s' % e)
        return
    for e in p.errors:
        fail('dashboard html: %s' % e)
    if p.stack:
        fail('dashboard html: unclosed element(s): %s'
             % ', '.join(e['tag'] for e in p.stack))
    root = p.root
    if root is None:
        fail('dashboard html: no elements found')
        return

    nodes = list(walk(root))
    app_nodes = [n for n in nodes if n['id'] == 'app']
    if len(app_nodes) != 1:
        fail('dashboard html: expected exactly one element with id="app", '
             'found %d' % len(app_nodes))
        return
    app = app_nodes[0]
    if 'app' not in app['classes']:
        fail('dashboard html: the #app element must carry class "app"')

    head_ok = False
    for n in nodes:
        if n['tag'] != 'head':
            continue
        for c in n['children']:
            if c['tag'] == 'link':
                rel = (c['attrs'].get('rel') or '').lower()
                href = (c['attrs'].get('href') or '').lower()
                if 'stylesheet' in rel and 'styles.css' in href:
                    head_ok = True
    if not head_ok:
        fail('dashboard html: <link rel="stylesheet" href="styles.css"> '
             'must appear in <head>')

    shell = [c for c in app['children']
             if c['tag'] == 'div' and 'shell' in c['classes']]
    if len(shell) != 1:
        fail('dashboard html: the #app element must contain exactly one '
             'div.shell, found %d' % len(shell))
        return
    sh = shell[0]
    for tg, cls in (('header', 'topbar'), ('aside', 'sidebar'),
                    ('main', 'main')):
        if not any(c['tag'] == tg and cls in c['classes']
                   for c in sh['children']):
            fail('dashboard html: div.shell must directly contain %s.%s'
                 % (tg, cls))

    sidebar = [c for c in sh['children']
               if c['tag'] == 'aside' and 'sidebar' in c['classes']]
    if len(sidebar) != 1:
        fail('dashboard html: div.shell must directly contain exactly one '
             'aside.sidebar, found %d' % len(sidebar))
    else:
        stats = [n for n in walk(sidebar[0]) if n is not sidebar[0]
                 and n['tag'] == 'div' and 'stat' in n['classes']]
        if len(stats) < 2:
            fail('dashboard html: expected at least 2 .stat elements in the '
                 'sidebar, found %d' % len(stats))

    main = [c for c in sh['children']
            if c['tag'] == 'main' and 'main' in c['classes']]
    if len(main) != 1:
        fail('dashboard html: div.shell must directly contain exactly one '
             'main.main, found %d' % len(main))
        return
    grids = [n for n in walk(main[0]) if n is not main[0]
             and n['tag'] == 'div' and 'card-grid' in n['classes']]
    if len(grids) != 1:
        fail('dashboard html: main.main must contain a single div.card-grid, '
             'found %d' % len(grids))
        return
    cards = [n for n in walk(grids[0]) if n is not grids[0]
             and n['tag'] == 'div' and 'card' in n['classes']]
    if len(cards) < 8:
        fail('dashboard html: expected at least 8 .card elements, found %d'
             % len(cards))


# --------------------------------------------------------------------------
# Fixture evaluation
# --------------------------------------------------------------------------

def evaluate_fixture(fixture_path, expected_path, sheet):
    with open(fixture_path) as fh:
        fixture = json.load(fh)
    with open(expected_path) as fh:
        expected = json.load(fh)
    viewport = float(fixture['viewport_width'])
    root = build_dom(fixture['root'])
    nodes = list(all_nodes(root))
    label = os.path.basename(os.path.dirname(fixture_path))

    def is_root(n):
        return n is root

    def ctype():
        cmap = {}
        for n in nodes:
            props = resolved_props(n, is_root, sheet, viewport, None)
            ct = props.get('container-type')
            cmap[id(n)] = norm(ct) if ct else None
        return cmap

    ctmap = ctype()
    cache = {}

    def custom_props(n):
        if n is None:
            return {}
        if id(n) in cache:
            return cache[id(n)]
        base = custom_props(n.parent)
        own = resolved_props(n, is_root, sheet, viewport, ctmap)
        merged = dict(base)
        for k, v in own.items():
            if k.startswith('--'):
                merged[k] = resolve_vars(norm(v), merged)
        cache[id(n)] = merged
        return merged

    def final_value(n, prop):
        props = resolved_props(n, is_root, sheet, viewport, ctmap)
        if prop not in props:
            return None
        return resolve_vars(norm(props[prop]), custom_props(n))

    for cls, want in expected.get('expect', {}).items():
        targets = [n for n in nodes if cls in n.classes]
        if not targets:
            fail('%s: no node with class %r in fixture' % (label, cls))
            continue
        for n in targets:
            for prop, wv in want.items():
                got = final_value(n, prop)
                if got is None:
                    fail('%s: %s.%s: property %r not resolved'
                         % (label, cls, n.dom_id(), prop))
                elif got != norm(str(wv)):
                    fail('%s: %s.%s: %s resolved to %r want %r'
                         % (label, cls, n.dom_id(), prop, got, norm(str(wv))))


def main(argv):
    css_path, html_path, hidden_dir = argv[1], argv[2], argv[3]
    if not os.path.exists(css_path):
        fail('missing deliverable %s' % css_path)
        _report()
        return 1
    if not os.path.exists(html_path):
        fail('missing deliverable %s' % html_path)
        _report()
        return 1

    css_text = open(css_path, encoding='utf-8', errors='replace').read()
    sheet, warnings, all_decls = parse_stylesheet(css_text)
    for w in warnings:
        print('notice: ' + w)

    structural_checks(sheet, all_decls)
    html_checks(html_path)

    hidden_cases = sorted(
        n for n in os.listdir(hidden_dir)
        if os.path.isdir(os.path.join(hidden_dir, n)))
    if len(hidden_cases) < 2:
        fail('expected >= 2 hidden cases')
    for case in hidden_cases:
        case_dir = os.path.join(hidden_dir, case)
        fx = os.path.join(case_dir, 'fixture.json')
        ex = os.path.join(case_dir, 'expected.json')
        if not (os.path.exists(fx) and os.path.exists(ex)):
            fail('%s: missing fixture.json/expected.json' % case)
            continue
        evaluate_fixture(fx, ex, sheet)

    return _report()


def _report():
    if failures:
        print('FAILURES (%d):' % len(failures))
        for f in failures:
            print('  - ' + f)
        return 1
    print('ALL PASS')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main(sys.argv))
    except Exception as e:
        print('RESOLVER EXCEPTION: %r' % (e,))
        sys.exit(1)