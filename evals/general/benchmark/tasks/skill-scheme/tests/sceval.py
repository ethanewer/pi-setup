import sys

def tokenize(s):
    s = s.replace('(', ' ( ').replace(')', ' ) ').replace("'", " ' ")
    return s.split()

def atom(tok):
    try: return int(tok)
    except ValueError:
        try: return float(tok)
        except ValueError:
            if tok == '#t': return True
            if tok == '#f': return False
            return tok

def parse_expr(tokens):
    tok = tokens.pop(0)
    if tok == "'":
        return ['quote', parse_expr(tokens)]
    if tok == '(':
        L=[]
        while tokens and tokens[0] != ')':
            L.append(parse_expr(tokens))
        if not tokens: raise SyntaxError("unexpected EOF")
        tokens.pop(0)
        return L
    if tok == ')': raise SyntaxError("unexpected )")
    return atom(tok)

def parse(prog):
    tokens = tokenize(prog)
    result=[]
    while tokens:
        result.append(parse_expr(tokens))
    return result

def to_str(x):
    if x is True: return '#t'
    if x is False: return '#f'
    if isinstance(x, list): return '('+' '.join(to_str(e) for e in x)+')'
    if isinstance(x, float) and x==int(x): return str(int(x))
    return str(x)

class SchemeError(Exception): pass

def truthy(v):
    return v is not False and v is not None

def evl(x, env):
    if isinstance(x, (int,float,bool)): return x
    if not isinstance(x, list):
        if x in env: return env[x]
        return x
    if not x: return []
    op = x[0]
    if isinstance(op, list):
        fn = evl(op, env)
        args=[evl(a,env) for a in x[1:]]
        return fn(*args)
    if op == 'quote': return x[1]
    if op == 'if':
        _,t,c,a = x
        return evl(c, env) if truthy(evl(t,env)) else evl(a,env)
    if op == 'cond':
        for p in x[1:]:
            if truthy(evl(p[0], env)):
                return evl(p[1], env)
        return False
    if op == 'begin':
        r=None
        for e in x[1:]: r=evl(e,env)
        return r
    if op == 'and':
        r=True
        for e in x[1:]:
            v=evl(e,env)
            if v is False: return False
            r=v
        return r
    if op == 'or':
        for e in x[1:]:
            v=evl(e,env)
            if v is not False: return v
        return False
    if op == 'not':
        return evl(x[1],env) is False
    if op == 'define':
        if isinstance(x[1], list):
            name, params, body = x[1][0], x[1][1:], x[2]
            env[name] = make_fn(params, body, env)
        else:
            env[x[1]] = evl(x[2], env)
        return None
    if op == 'lambda':
        return make_fn(x[1], x[2], env)
    if op == 'let':
        binds={}
        for (v,e) in x[1]:
            binds[v]=evl(e,env)
        return evl(x[2], dict(env, **binds))
    if op in env:
        fn = env[op]
    else:
        raise SchemeError('undefined:'+str(op))
    args=[evl(a,env) for a in x[1:]]
    if callable(fn): return fn(*args)
    raise SchemeError('not callable:'+to_str(op))

def make_fn(params, body, env):
    def f(*args):
        if len(args)!=len(params): raise SchemeError('arity mismatch')
        return evl(body, dict(env, **dict(zip(params, args))))
    return f

def stdlib(env):
    env['+']=lambda *a: sum(a)
    env['*']=lambda *a: __import__('functools').reduce(lambda x,y:x*y, a, 1)
    env['-']=lambda x,y=None: -x if y is None else x-y
    def _div(x,y):
        if isinstance(x,(int,float)) and y==0:
            raise ZeroDivisionError('division by zero')
        r=x/y
        return int(r) if isinstance(r,float) and r.is_integer() else r
    env['/']=_div
    env['mod']=lambda a,b: a%b
    env['abs']=abs
    env['min']=lambda *a: min(a)
    env['max']=lambda *a: max(a)
    env['=']=lambda a,b: a==b
    env['<']=lambda a,b: a<b
    env['>']=lambda a,b: a>b
    env['<=']=lambda a,b: a<=b
    env['>=']=lambda a,b: a>=b
    env['car']=lambda a: a[0]
    env['cdr']=lambda a: a[1:]
    env['cons']=lambda a,b: [a]+list(b)
    env['list']=lambda *a: list(a)
    env['null?']=lambda a: a==[] or a is None
    env['eq?']=lambda a,b: a==b
    env['zero?']=lambda a: a==0
    env['length']=lambda a: len(a)

def truthy(v):
    return v is not False and v is not None

def run(prog):
    env={}
    stdlib(env)
    out=[]
    for expr in parse(prog):
        if isinstance(expr, list) and expr and expr[0]=='define':
            evl(expr, env)
            continue
        r=evl(expr, env)
        if r is not None:
            out.append(to_str(r))
    return '\n'.join(out)

if __name__=='__main__':
    prog=open(sys.argv[1]).read()
    sys.stdout.write(run(prog)+'\n')