#!/usr/bin/env bash
# RIDGE verifier.  Executes every deliverable:
#   * framework.py  -> imported and driven against /tests/hidden cases
#                      (stability / precision / mixed / bags / gradient);
#   * model.pt      -> loaded, checked finite + converged below target;
#   * train.log     -> parsed for faithful config + final loss;
#   * train.py      -> re-run on an independent hidden config and required to
#                      converge below target and write model + log.
# Reward is 1 only if every check passes.
set -uo pipefail

python3 - <<'PY'
import numpy as np, json, os, re, sys, subprocess, importlib.util

HID = '/tests/hidden'

def check(cond, msg):
    if not cond:
        print('FAIL:', msg)
        sys.exit(1)

# --- load the agent's deliverable framework ---
spec = importlib.util.spec_from_file_location("fw", "/app/framework.py")
F = importlib.util.module_from_spec(spec)
spec.loader.exec_module(F)

# 1) numerical stability: extreme / tiny / single / variable inputs (fp64)
s = json.load(open(os.path.join(HID, 'stability.json')))
for i, c in enumerate(s['cases']):
    w, lse = F.attention_softmax(c['logits'], axis=c['axis'], dtype='fp64')
    w = np.asarray(w); lse = np.asarray(lse)
    check(bool(np.all(np.isfinite(w))) and bool(np.all(np.isfinite(lse))),
          'stability[%d] produced non-finite output' % i)
    err = float(np.abs(w.astype(np.float64).sum(axis=c['axis']) - 1.0).max())
    check(err < 1e-9, 'stability[%d] weights do not sum to 1 (err=%g)' % (i, err))

# 2) precision: exact dtype + per-precision sum tolerance; fp16->fp32 mixed
p = json.load(open(os.path.join(HID, 'precision.json')))
for dt in p['dtypes']:
    w, lse = F.attention_softmax(p['logits'], axis=-1, dtype=dt)
    w = np.asarray(w); lse = np.asarray(lse)
    check(bool(np.all(np.isfinite(w))) and bool(np.all(np.isfinite(lse))),
          'precision[%s] non-finite' % dt)
    check(np.issubdtype(w.dtype, F.dtype_for(dt)),
          'precision[%s] wrong dtype %s' % (dt, w.dtype))
    tol = float(F.dtype_sum_tolerance(dt))
    err = float(np.abs(w.astype(np.float64).sum(axis=-1) - 1.0).max())
    check(err <= tol, 'precision[%s] sum err %g > tol %g' % (dt, err, tol))
mi = p['mixed_input']
m = F.BagModel(3, dtype=mi['model_dtype'], seed=2)
items = np.asarray(mi['items'], dtype=F.dtype_for(mi['input_dtype']))
pred = m.forward(items)
check(bool(np.isfinite(pred)) and 0.0 < pred < 1.0, 'mixed pred not in (0,1)')
g = m.backward(1)
for k, v in g.items():
    check(bool(np.isfinite(v)) and v > 0.0, 'mixed grad %s not finite/nonzero' % k)

# 3) BagModel forward across variable / single-instance / tiny / large bags
bg = json.load(open(os.path.join(HID, 'bags.json')))
m = F.BagModel(bg['d'], dtype='fp32', seed=bg['seed'])
for i, case in enumerate(bg['bag_cases']):
    pred = m.forward(case['items'])
    check(bool(np.isfinite(pred)) and 0.0 < pred < 1.0,
          'bag[%d] pred %r not finite in (0,1)' % (i, pred))

# 4) gradient flow: every parameter gets a finite nonzero gradient
gr = json.load(open(os.path.join(HID, 'gradient.json')))
m = F.BagModel(gr['d'], dtype='fp32', seed=gr['seed'])
for items, t in zip(gr['bags'], gr['targets']):
    m.forward(items)
    g = m.backward(t)
    for k, v in g.items():
        check(bool(np.isfinite(v)) and v > 0.0,
              'grad %s not finite/nonzero' % k)

# 5) deliverable model.pt: valid npz, finite params, converged below target
check(os.path.exists('/app/model.pt'), 'model.pt missing')
z = np.load('/app/model.pt')
for k in ['Wa', 'Wo', 'bo', 'dtype', 'dims', 'final_loss']:
    check(k in z, 'model.pt missing key %s' % k)
fl = float(z['final_loss'])
check(bool(np.isfinite(fl)), 'model.pt final_loss not finite')
check(fl < 0.02, 'model.pt final_loss %g >= 0.02' % fl)
for k in ['Wa', 'Wo', 'bo']:
    d = z[k]
    check(bool(np.all(np.isfinite(d))) and bool(np.any(d != 0)),
          'model.pt %s non-finite or all-zero' % k)

# 6) deliverable train.log: config header + epoch lines + converged final loss
check(os.path.exists('/app/train.log'), 'train.log missing')
txt = open('/app/train.log').read()
check('# config' in txt, 'train.log has no # config header')
check(re.search(r'epoch=\d+ loss=', txt) is not None, 'train.log has no epoch lines')
mfin = re.search(r'# final_loss=([0-9.eE+-]+)', txt)
check(mfin is not None, 'train.log has no # final_loss line')
check(float(mfin.group(1)) < 0.02,
      'train.log final_loss %s >= 0.02' % mfin.group(1))

# 7) train.py is a runnable deliverable that generalizes: re-run it on a hidden
#    config and require convergence below its target, plus valid model/log.
sub_cfg = ['python3', '/app/train.py',
           '--dims', '6', '--bags', '40', '--max-items', '10', '--noise', '0.3',
           '--iters', '300', '--lr', '0.08', '--dtype', 'fp32', '--seed', '3',
           '--target', '0.05',
           '--out', '/app/hmodel.pt', '--log', '/app/htrain.log']
r = subprocess.run(sub_cfg, capture_output=True, text=True, cwd='/app')
check(r.returncode == 0, 'train.py re-run failed: ' + r.stderr[-500:])
mfin2 = re.search(r'FINAL_LOSS=([0-9.eE+-]+)', r.stdout)
check(mfin2 is not None, 'train.py re-run printed no FINAL_LOSS')
check(float(mfin2.group(1)) < 0.05,
      'hidden train.final_loss %s >= 0.05' % mfin2.group(1))
hlog = open('/app/htrain.log').read()
check('# config' in hlog, 'hidden train.log has no # config header')
check(re.search(r'epoch=\d+ loss=', hlog) is not None,
      'hidden train.log has no epoch lines')
check(os.path.exists('/app/hmodel.pt'), 'hidden model.pt missing')

print('ALL_CHECKS_PASS')
PY
rc=$?

reward=0
if [ $rc -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
