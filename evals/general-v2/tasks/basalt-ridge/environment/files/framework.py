"""framework.py -- RIDGE, a small, CPU-only, pure-Python autograd deep-learning
framework built from source.  It uses no GPU and no prebuilt ML library: the
autodiff engine, the numerics and the composed model are implemented here from
numpy primitives.

Surfaces:
  * a reverse-mode autodiff engine (Tensor + function ops + backward),
  * a numerically stable, max-subtracted softmax over a chosen axis,
  * a numerically stable sigmoid (no overflow for extreme z),
  * dtype-aware casting (fp16 / fp32 / fp64) with finite outputs and a
    per-precision attention-sum tolerance,
  * `class BagModel`: a composed bag-attention classifier
        score   = items @ Wa
        attn    = softmax(score, axis=items)
        context = sum_i attn_i * items_i
        logit   = context @ Wo + bo
        prob    = sigmoid(logit)
    whose whole forward is connected so one backward populates a gradient on
    every parameter (Wa, Wo, bo) -- no stage is detached.
  * `attention_softmax(logits, axis, dtype)` -- the standalone stable softmax
    primitive used by the precision / stability checks.
"""

import numpy as np

# ---------------------------------------------------------------------------
# dtype surface
# ---------------------------------------------------------------------------
DTYPES = {'fp16': np.float16, 'fp32': np.float32, 'fp64': np.float64}

def dtype_for(name):
    """Map an fp16/fp32/fp64 (or 'mixed' -> fp32) tag to a numpy dtype."""
    name = str(name).lower()
    if name == 'mixed':
        name = 'fp32'
    return DTYPES[name]

# attention-sum tolerance accepted for each configured precision
SUM_TOL = {'fp16': 1e-1, 'fp32': 1e-4, 'fp64': 1e-9}

def dtype_sum_tolerance(dtype):
    return SUM_TOL[str(dtype).lower()]


# ---------------------------------------------------------------------------
# autodiff engine
# ---------------------------------------------------------------------------
def _as(x):
    if isinstance(x, Tensor):
        return x
    return Tensor(np.asarray(x, dtype=float), requires_grad=False)


class Tensor(object):
    def __init__(self, data, requires_grad=True, parents=None, backward=None,
                 name=''):
        self.data = np.asarray(data, dtype=float)
        self.requires_grad = requires_grad
        self.grad = np.zeros_like(self.data) if requires_grad else None
        self.parents = parents if parents is not None else []
        self._backward = backward
        self.name = name

    @property
    def T(self):
        return transpose(self)

    def zero_grad(self):
        if self.grad is not None:
            self.grad.fill(0.0)


def _acc(base, amount):
    if not base.requires_grad or amount is None:
        return
    base.grad = np.add(base.grad, np.asarray(amount, dtype=float))


def transpose(a):
    a = _as(a)
    out = a.data.T
    def bwd(g):
        _acc(a, g.T)
    return Tensor(out, requires_grad=True, parents=[a], backward=bwd)


def matmul(a, b):
    a = _as(a)
    b = _as(b)
    out = a.data @ b.data
    def bwd(g):
        _acc(a, g @ b.data.T)
        _acc(b, a.data.T @ g)
    return Tensor(out, requires_grad=True, parents=[a, b], backward=bwd)


def add(a, b):
    a = _as(a)
    b = _as(b)
    out = a.data + b.data
    def bwd(g):
        _acc(a, g)
        if b.data.shape == a.data.shape:
            _acc(b, g)
        else:
            _acc(b, g.sum(axis=0, keepdims=True))
    return Tensor(out, requires_grad=True, parents=[a, b], backward=bwd)


def sigmoid_op(a):
    """Sigmoid computed without overflow for extreme z (0/1 partitioning)."""
    a = _as(a)
    z = np.asarray(a.data, dtype=float)
    p = np.zeros_like(z)
    pos = z >= 0
    neg = ~pos
    p[pos] = 1.0 / (1.0 + np.exp(-z[pos]))
    p[neg] = np.exp(z[neg]) / (1.0 + np.exp(z[neg]))
    def bwd(g):
        _acc(a, g * p * (1.0 - p))
    return Tensor(p, requires_grad=True, parents=[a], backward=bwd)


def softmax(scores, axis=0):
    """Max-subtracted softmax over `axis`, as an autograd op."""
    s = _as(scores)
    m = s.data.max(axis=axis, keepdims=True)
    e = np.exp(s.data - m)
    p = e / e.sum(axis=axis, keepdims=True)
    def bwd(g):
        g = np.asarray(g, dtype=float)
        dim = (g * p).sum(axis=axis, keepdims=True)
        _acc(s, p * (g - dim))
    return Tensor(p, requires_grad=True, parents=[s], backward=bwd)


def backward(root):
    """Reverse-mode autodiff from the scalar root tensor."""
    seen = set()
    order = []
    def visit(n):
        if id(n) in seen:
            return
        seen.add(id(n))
        for ch in n.parents:
            visit(ch)
        order.append(n)
    visit(root)
    for n in reversed(order):
        if n.requires_grad and n.grad is not None and n._backward is not None:
            n._backward(n.grad)


# ---------------------------------------------------------------------------
# standalone stable numerics
# ---------------------------------------------------------------------------
def stable_sigmoid(z):
    z = np.asarray(z, dtype=float)
    out = np.zeros_like(z)
    pos = z >= 0
    neg = ~pos
    out[pos] = 1.0 / (1.0 + np.exp(-z[pos]))
    out[neg] = np.exp(z[neg]) / (1.0 + np.exp(z[neg]))
    return out


def attention_softmax(logits, axis=-1, dtype='fp32'):
    """Stable softmax over `axis`, in the requested dtype.

    Returns the 2-tuple (weights, logsumexp).  `weights` is the normalized
    attention in the exact configured dtype.  Must keep weights finite and
    summing to 1 over `axis` up to SUM_TOL[dtype] for every regime.
    """
    x = np.asarray(logits, dtype=float)
    # naive: exp() taken directly on the raw logits (no max subtraction)
    e = np.exp(x)
    s = np.sum(e, axis=axis, keepdims=True)
    p = e / s
    dt = dtype_for(dtype)
    lse = np.log(s)
    return p.astype(dt), np.squeeze(lse, axis=axis).astype(dt)


class _BCE(object):
    """Binary cross-entropy of a sigmoid output vs a target in {0, 1}, with
    its correct backward gradient dL/dphi = (phi - target)/(phi(1-phi)+eps)."""

    def __call__(self, pred, target):
        epsilon = 1e-12
        o = float(pred.data.reshape(-1)[0])
        o = min(max(o, epsilon), 1.0 - epsilon)
        target = float(target)
        loss = float(-(target * np.log(o) + (1 - target) *
                       np.log(1.0 - o)))
        def bwd(g):
            # true BCE gradient direction w.r.t. the sigmoid output node
            grad = -float((o - target) / (o * (1.0 - o) + epsilon))
            _acc(pred, np.array([[grad]]) *
                 float(np.asarray(g).reshape(-1)[0]))
        return Tensor(np.array([[loss]]), requires_grad=True, parents=[pred],
                      backward=bwd)


bce_loss = _BCE()


# ---------------------------------------------------------------------------
# the composed bag-attention classifier
# ---------------------------------------------------------------------------
class BagModel:
    """Bag-attention classifier.

      forward(items): items is (n_items, d).
      backward(target): seeds the BCE loss fed by the latest forward, and
          returns {name: max_abs_grad} for every parameter, guaranteeing each
          gradient is finite and non-zero (no detached stage).
    """

    def __init__(self, d, dtype='fp32', seed=0, init_scale=0.3):
        rg = np.random.default_rng(seed)
        self.d = int(d)
        self.precision = str(dtype).lower()
        self.dtype = DTYPES[self.precision]
        self.scale = float(init_scale)
        self.Wa = Tensor(rg.normal(0.0, self.scale, (self.d, 1)), name='Wa')
        self.Wo = Tensor(rg.normal(0.0, self.scale, (self.d, 1)), name='Wo')
        self.bo = Tensor(np.zeros((1, 1)), name='bo')
        self._last = None

    def parameters(self):
        return [self.Wa, self.Wo, self.bo]

    def forward(self, items):
        X = np.asarray(items, dtype=float)
        if X.ndim == 1:
            X = X.reshape(1, -1)
        if X.shape[1] != self.d:
            raise ValueError('bag inner dimension %d != model dim %d'
                             % (X.shape[1], self.d))
        Xt = _as(X)
        score = matmul(Xt, self.Wa)                 # (n, 1)
        attn = softmax(score, axis=0)               # (n, 1) over items
        context = matmul(attn.T, Xt)                # (1, d)
        logit = add(matmul(context, self.Wo), self.bo)   # (1, 1)
        prob = sigmoid_op(logit)                    # (1, 1)
        self._last = (prob, attn, score)
        return float(np.asarray(prob.data, dtype=self.dtype).reshape(-1)[0])

    def last_attention(self, dtype=None):
        if self._last is None:
            return None
        dt = self.dtype if dtype is None else dtype_for(dtype)
        return np.asarray(self._last[1].data, dtype=float).astype(dt)

    def loss_node(self, target=0.0):
        return bce_loss(self._last[0], target)

    def loss_value(self, target=0.0):
        return float(self.loss_node(target).data.reshape(-1)[0])

    def backward(self, target=0.0):
        out = self._last[0]
        for pr in self.parameters():
            pr.zero_grad()
        loss = bce_loss(out, target)
        loss.grad = np.array([[1.0]])
        backward(loss)
        report = {}
        for pr in self.parameters():
            g = np.asarray(pr.grad, dtype=float)
            finite = bool(np.all(np.isfinite(g)))
            nrm = float(np.abs(g).max()) if g.size else 0.0
            report[pr.name] = nrm
            if not finite:
                raise ArithmeticError('non-finite gradient on %s' % pr.name)
        return report