#!/usr/bin/env python3
"""train.py -- training entrypoint for the RIDGE bag-attention classifier.

Builds a framework.BagModel, manufactures a deterministic bag-classification
dataset, trains the model with plain full-batch SGD, records a reviewable log
(one '# config <...>' header line, '# epoch=<n> loss=<v>' per epoch, and a
'# final_loss=<v>' tail line), and writes the trained weights.

Usage:
    python3 /app/train.py [options]

Options (defaults shown; the grader may re-run with different values):
    --dims 8          feature dimensionality per item
    --bags 24         number of training bags
    --max-items 12    max items drawn into a bag
    --noise 0.4       per-item noise std
    --iters 500       training epochs
    --lr 0.05         SGD step size
    --dtype fp32      model precision: fp16/fp32/fp64
    --init 0.3        init standard deviation
    --seed 0          RNG seed
    --target 0.0      early-stop / acceptance loss threshold
    --out /app/model.pt
    --log /app/train.log

Prints FINAL_LOSS=<value> and MODEL_WRITTEN=<path> on success.
"""

import argparse
import os

import numpy as np

import framework as F


def build_dataset(d, bags, max_items, noise, seed):
    rg = np.random.default_rng(seed)
    c0 = rg.normal(-1.0, 0.5, (1, d))
    c1 = rg.normal(1.0, 0.5, (1, d))
    data = []
    for _ in range(bags):
        y = 1 if rg.random() < 0.5 else 0
        c = c1 if y else c0
        n = int(rg.integers(1, max_items + 1))
        items = c + rg.normal(0.0, noise, (n, d))
        data.append((items, y))
    return data


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument('--dims', type=int, default=8)
    ap.add_argument('--bags', type=int, default=24)
    ap.add_argument('--max-items', type=int, default=12)
    ap.add_argument('--noise', type=float, default=0.4)
    ap.add_argument('--iters', type=int, default=500)
    ap.add_argument('--lr', type=float, default=0.05)
    ap.add_argument('--dtype', default='fp32')
    ap.add_argument('--init', type=float, default=0.3)
    ap.add_argument('--seed', type=int, default=0)
    ap.add_argument('--target', type=float, default=0.0)
    ap.add_argument('--out', default='/app/model.pt')
    ap.add_argument('--log', default='/app/train.log')
    args = ap.parse_args()

    d = args.dims
    model = F.BagModel(d, dtype=args.dtype, seed=args.seed,
                       init_scale=args.init)
    data = build_dataset(d, args.bags, args.max_items, args.noise, args.seed)

    cfg = ('dims=%d bags=%d max_items=%d noise=%g iters=%d lr=%g '
           'dtype=%s init=%g seed=%d' % (
               args.dims, args.bags, args.max_items, args.noise, args.iters,
               args.lr, args.dtype, args.init, args.seed))
    log_lines = ['# config %s' % cfg,
                 '# framework RIDGE cpu-only autograd (pure numpy)']

    lr = args.lr
    final_loss = float('inf')
    for epoch in range(args.iters):
        total = 0.0
        for items, y in data:
            for pr in model.parameters():
                pr.zero_grad()
            model.forward(items)
            loss = model.loss_node(y)
            loss.grad = np.array([[1.0]])
            F.backward(loss)
            total += float(loss.data.reshape(-1)[0])
            for pr in model.parameters():
                pr.data -= lr * pr.grad
        epoch_loss = total / len(data)
        log_lines.append('epoch=%d loss=%.6f' % (epoch, epoch_loss))
        final_loss = epoch_loss
        if args.target > 0 and epoch_loss < args.target:
            log_lines.append('# early_stop reached at epoch %d' % epoch)
            break

    log_lines.append('# final_loss=%.6f' % final_loss)
    log_lines.append('# model_out=%s' % args.out)

    for path in (args.out, args.log):
        ddir = os.path.dirname(os.path.abspath(path))
        if ddir:
            os.makedirs(ddir, exist_ok=True)
    with open(args.out, 'wb') as fh:
        np.savez_compressed(
            fh, Wa=model.Wa.data, Wo=model.Wo.data, bo=model.bo.data,
            dtype=np.array(args.dtype), dims=np.array(d),
            final_loss=np.array(final_loss))
    with open(args.log, 'w') as fh:
        fh.write('\n'.join(log_lines) + '\n')

    print('FINAL_LOSS=%.6f' % final_loss)
    print('MODEL_WRITTEN=%s' % args.out)


if __name__ == '__main__':
    main()