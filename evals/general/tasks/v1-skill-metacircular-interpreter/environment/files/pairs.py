def cons(a, b):  return {"car": a, "cdr": b}
def car(p):      return p["car"]
def cdr(p):      return p["cdr"]
NIL = None

def is_nil(x):   return x is None
def is_atom(x):  return not isinstance(x, dict)