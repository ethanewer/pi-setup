# TODO — Add tasks for 3 uncovered competencies

722/726 tb2.1 competencies are covered. 3 of the 4 uncovered ones were
misclassified as infeasible; only the kernel rebuild is genuinely blocked.

## Genuinely infeasible (leave as-is)

- **C-c65bea8a** (kernel rebuild → tb2.1 `build-linux-kernel-qemu`): Requires
  building Linux from source and booting in QEMU with KVM. Not possible in
  Docker on macOS. Documented waiver.

## Feasible — author tasks for these

### 1. C-6f29d769 — Multi-service interactive negotiation

tb2.1 task: `find-restaurant`. Agent calls simulated people via interactive
bash scripts that POST to Flask microservices, obtains an authentication
phrase from one service, uses it to unlock another, then aggregates
preferences/schedules to make a decision.

What a v3 task needs:
- Docker Compose stack with 2-3 Flask microservices (simulated "people" with
  different preferences/schedules)
- Interactive bash client scripts that the agent must use (read + respond)
- Authentication flow: service A gives a phrase, service B requires it
- Verifier checks the final output file (reservation/decision) against
  expected values derived from the hidden service state
- Must not copy tb2.1's `find-restaurant` scenario — use a different domain
  (e.g., scheduling a team offsite, coordinating a multi-vendor deployment)

### 2. C-2e082c47 — Triton learned-gate kernel (CPU interpret mode)

tb2.1 task: `triton-interpret`. Agent implements a gated RMSNorm
transformation in pure Triton, handling optional gate parameters and various
batch/sequence/dimension shapes. Runs with `TRITON_INTERPRET=1` on CPU.

What a v3 task needs:
- A PyTorch reference implementation (different architecture than tb2.1's
  gated RMSNorm — e.g., gated attention, gated MLP, or gated convolution)
- Agent must implement the Triton kernel with `TRITON_INTERPRET=1`
- Verifier runs the agent's kernel against the PyTorch reference on multiple
  shapes (edge cases: batch=1, seq=1, gate=None, non-power-of-2 dims)
- Checks: no torch/numpy inside `@triton.jit` kernels, numerical tolerance
  (rtol=1e-4, atol=1e-6), correct dtype handling

### 3. C-c34cf87e — Triton pure tl-op reductions (no tl.sum)

Same tb2.1 task (`triton-interpret`) but the specific constraint: implement
reductions using only `tl` ops, no `tl.sum`. Forces manual accumulation
patterns.

What a v3 task needs:
- Can be the same task as C-2e082c47 if the verifier also checks for absence
  of `tl.sum` (one task covers both competencies)
- Or a separate task focused on reduction patterns (softmax, layer norm,
  attention scores) with `tl.sum` explicitly forbidden
- Verifier greps the agent's solution for `tl.sum` / `triton.language.sum`
  and fails if found

## Effort estimate

| Task | Complexity | Est. time |
|---|---|---|
| C-6f29d769 (multi-service) | High — Docker Compose, Flask services, interactive clients | 2-3 hours |
| C-2e082c47 + C-c34cf87e (Triton) | Medium — single task can cover both; Triton interpret mode well-documented | 1-2 hours |
| **Total** | | **3-5 hours** |

## After authoring

1. `python3 tools/lint_tasks.py` — 0 problems
2. Oracle verification for each new task (reward=1.0)
3. Rebuild coverage: `python3 tools/build_coverage.py && python3 tools/check_tb21_coverage.py`
4. Re-run independence audit: `python3 tools/audit_independence_stream.py`
5. `python3 tools/suite_report.py` → SUITE PASS
6. Commit + push + upload to HF
