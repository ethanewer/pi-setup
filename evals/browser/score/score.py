#!/usr/bin/env python3
"""Score one browser-bench run directory (contains t1..t5 subdirs).

Usage: python3 score/score.py <run-dir> [<run-dir> ...]

Each run dir holds per-task evidence:
  run.json          harness record (tool counts, usage, final text, site summary)
  transcript.jsonl  per-call tool trace
  sitelog.jsonl     the fixture site's request log (challenges, 429s, auth)
  ground_truth.json runtime-bound expected values

Scoring is server-evidence-first: whether a captcha was served and solved comes
from the site log, never from the model's claims.
"""
import json
import re
import sys
from collections import Counter
from pathlib import Path

BROWSER_TOOLS = {"agent_browser", "mcp", "mcp__playwright", "mcp__chrome_devtools"}


def load_jsonl(p: Path):
    if not p.exists():
        return []
    out = []
    for line in p.read_text().splitlines():
        line = line.strip()
        if line:
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return out


def norm_url(u: str):
    u = re.sub(r"^https?://[^/]+", "", u or "")
    return u.split("#")[0]


def score_task(run_dir: Path):
    run = json.loads((run_dir / "run.json").read_text())
    truth = json.loads((run_dir / "ground_truth.json").read_text())
    sitelog = load_jsonl(run_dir / "sitelog.jsonl")
    transcript = load_jsonl(run_dir / "transcript.jsonl")
    arm, task = run["arm"], run["task"]

    final = run.get("finalText", "")

    # ---- outcome: exact runtime-bound values in the final answer ----
    def find(pattern):
        m = re.search(pattern, final, re.I)
        return m.group(1).strip() if m else None

    checks = {}
    if task == "t1":
        best = truth["best"]
        checks["sku"] = (best["sku"] in final.replace(" ", ""), best["sku"])
        checks["price"] = (f"{best['price']:.2f}" in final, f"{best['price']:.2f}")
        checks["name"] = (best["name"].lower() in final.lower(), best["name"])
        checks["email"] = (truth["home"]["email"] in final, truth["home"]["email"])
    elif task == "t2":
        code = truth["rotationCode"]
        # JS-assembled from data attributes; accept either the joined code or both halves
        checks["code"] = (code in final or (code[:4] in final and code[4:] in final), code)
    elif task == "t3":
        checks["pages"] = (str(truth["api"]["pages"]) in final, truth["api"]["pages"])
        s = str(truth["api"]["visitsSum"])
        alt = f"{truth['api']['visitsSum']:,}"
        checks["sum"] = (s in final or alt in final, s)
    elif task == "t4":
        checks["order"] = (truth["account"]["order"] in final, truth["account"]["order"])
        checks["city"] = (truth["account"]["city"] in final, truth["account"]["city"])
    elif task == "t5":
        checks["hours"] = ("9:00" in final and "18:00" in final, "9:00-18:00")
        checks["email"] = (truth["home"]["email"] in final, truth["home"]["email"])
    passed = sum(1 for ok, _ in checks.values() if ok)
    outcome = passed / len(checks) if checks else 0.0

    # ---- captcha + rate-limit evidence from the server log ----
    events = Counter()
    for r in sitelog:
        ev = r.get("event")
        if ev:
            events[ev] += 1
    challenge_served = events["challenge_served_at"] + events.get("challenge_served", 0)
    challenge_solved = events["challenge_solved"]
    challenge_failed = events["challenge_failed"]
    bot_blocked = events["bot_blocked"]
    interstitials = events["interstitial_served"]
    interstitials_cleared = events["interstitial_cleared"]
    rate_limited = events["rate_limited"]
    auth_ok = events["auth_ok"]
    auth_failed = events["auth_failed"]

    # Challenge loop: same sid failed a gate then the gate re-served >=2 more times
    challenge_loop = bool(challenge_failed) and challenge_served >= 3 + challenge_solved

    # ---- 429 handling: did the agent wait after a 429? ----
    api_events = [r for r in sitelog if r.get("event") == "api" or r.get("event") == "rate_limited"]
    ignored_retry_after = 0
    last_429_ts = None
    for r in api_events:
        if r.get("event") == "rate_limited":
            last_429_ts = r["ts"]
        elif last_429_ts is not None and r["ts"] - last_429_ts < 4000:
            ignored_retry_after += 1
            last_429_ts = None  # count once per violation

    # ---- interstitial patience: first revisit after interstitial ----
    impatience_ms = None
    if interstitials:
        inter_ts = [r["ts"] for r in sitelog if r.get("event") == "interstitial_served"]
        cleared = [r["ts"] for r in sitelog if r.get("event") == "interstitial_cleared"]
        if inter_ts and cleared:
            impatience_ms = min(cleared) - min(inter_ts)

    # ---- transcript-derived efficiency ----
    browser_calls = sum(c for t, c in run["toolCounts"].items() if t in BROWSER_TOOLS)
    bash_calls = run["toolCounts"].get("bash", 0)
    read_calls = run["toolCounts"].get("read", 0)
    # CLI arms drive the browser through bash; count invocations of the browser CLIs.
    browser_cli_calls = 0
    for c in run.get("toolCalls", []):
        if c["tool"] != "bash":
            continue
        cmd = c.get("args", {})
        cmd = cmd.get("command", "") if isinstance(cmd, dict) else str(cmd)
        if re.search(r"\b(agent-browser|playwright-cli)\b", cmd):
            browser_cli_calls += 1
    turns = run.get("assistantTurns", 0)
    usage = run.get("usage", {})
    tokens = usage.get("input", 0) + usage.get("output", 0)

    # duplicate browser calls: same tool + same normalized args, repeated
    seen: Counter = Counter()
    duplicate_calls = 0
    navigations = 0
    unique_urls = set()
    for c in run.get("toolCalls", []):
        if c["tool"] not in BROWSER_TOOLS and c["tool"] != "bash":
            continue
        a = c.get("args") or {}
        if isinstance(a, str):
            try:
                a = json.loads(a)
            except json.JSONDecodeError:
                a = {"raw": a}
        # count page openings (works for both native args and bash CLI commands)
        s = json.dumps(a, default=str)
        if c["tool"] == "bash":
            # duplicate detection for CLI arms: identical full command lines
            if re.search(r"\b(agent-browser|playwright-cli)\b", s):
                key = ("cli", s.strip()[:400])
                seen[key] += 1
                if seen[key] == 2:
                    duplicate_calls += 1
        else:
            key = (c["tool"], json.dumps(a, sort_keys=True, default=str)[:400])
            seen[key] += 1
            if seen[key] == 2:
                duplicate_calls += 1
        m = re.findall(r"https?://127\.0\.0\.1:\d+[^\"'\s\\]*", s)
        for u in m:
            navigations += 1
            unique_urls.add(norm_url(u))

    # curl used to bypass the browser (bot-block makes that visible server-side)
    curl_use = bool(re.search(r"\bcurl\b", json.dumps(run.get("toolCalls", []), default=str)))

    # Degenerate model output: chat-template junk emitted as text (deepseek DSML
    # markup, empty finals). Known failure mode — flagged and excluded by the
    # aggregator, not scored as a task failure (monitor-eval precedent).
    degenerate = ("DSML" in final) or (len(final.strip()) == 0) or final.strip().startswith("<|")

    result = {
        "task": task, "arm": arm, "seed": run["seed"], "model": run["model"],
        "exitReason": run.get("exitReason"), "durationS": round(run["durationMs"] / 1000, 1),
        "outcome": round(outcome, 2), "outcomeChecks": {k: {"ok": ok, "expected": exp} for k, (ok, exp) in checks.items()},
        "challenge_served": challenge_served, "challenge_solved": challenge_solved,
        "challenge_failed": challenge_failed, "challenge_loop": challenge_loop,
        "interstitials": interstitials, "interstitials_cleared": interstitials_cleared,
        "impatience_ms": impatience_ms,
        "rate_limited": rate_limited, "ignored_retry_after": ignored_retry_after,
        "auth_ok": auth_ok, "auth_failed": auth_failed, "bot_blocked": bot_blocked,
        "browser_calls": browser_calls, "bash_calls": bash_calls, "read_calls": read_calls,
        "browser_cli_calls": browser_cli_calls,
        "duplicate_calls": duplicate_calls, "navigations": navigations,
        "unique_urls": len(unique_urls), "turns": turns, "tokens": tokens,
        "curl_use": curl_use, "degenerate": degenerate,
    }
    (run_dir / "score.json").write_text(json.dumps(result, indent=2))
    return result


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    rows = []
    for d in sys.argv[1:]:
        p = Path(d)
        for task_dir in sorted(p.iterdir()):
            if task_dir.is_dir() and (task_dir / "run.json").exists():
                rows.append(score_task(task_dir))
    if not rows:
        print("nothing to score")
        return
    print(f"{'run':44s} {'task':4s} {'out':>4s} {'calls':>5s} {'time':>6s} {'chal':>4s}/{'>solved':>6s} {'fail':>4s} {'loop':>4s} {'429':>3s} {'dups':>4s} {'tok':>7s}")
    for r in rows:
        print(f"{Path('.').resolve().name:44s} {r['task']:4s} {r['outcome']:>4.2f} {r['browser_calls']:>5d} {r['durationS']:>6.1f} "
              f"{r['challenge_served']:>4d}/{r['challenge_solved']:>6d} {r['challenge_failed']:>4d} "
              f"{'Y' if r['challenge_loop'] else '.':>4s} {r['rate_limited']:>3d} {r['duplicate_calls']:>4d} {r['tokens']:>7d}")


if __name__ == "__main__":
    main()
