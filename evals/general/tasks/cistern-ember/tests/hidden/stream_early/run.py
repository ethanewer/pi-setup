#!/usr/bin/env python3
"""Hidden case 1: streaming a large plain for-loop, stopping early.

Consumes only the first two chunks of generate_async() output for a template
whose body is a 300-item for-loop, then closes the stream. A fixed tree
closes every nested generator during that close and nothing leaks; a buggy
tree abandons the template generators and trio reports them.

Not part of the upstream test set: the upstream regression test only iterates
a 3-item list with a single __anext__.
"""
import asyncio
import gc
import sys
import warnings

import trio
from jinja2 import Template


def _leak_channel_live() -> tuple:
    """Self-test: the leak-detection channel must be live, or this case cannot
    discriminate a fixed tree from a silenced one.  Abandons the compiled root
    render generator of a tiny template WITHOUT aclose; on ANY tree (fixed or
    buggy) this leaks an '<<template>>.root' async generator whose 'garbage
    collected' ResourceWarning is reported through exactly the same finalizer
    channel the real leak uses.  Any silencing - a warnings filter, disabled
    asyncgen hooks, an edited trio finalizer, or a filter planted anywhere in
    the tree's allowed modules - suppresses this probe exactly like the real
    leak, so the probe cannot be selectively spared: anyone who silences the
    real diagnostic silences the probe, and the case then refuses to score.
    """
    import gc as _gc
    import warnings as _w
    import trio as _trio
    from jinja2 import Template as _Template

    probe = _Template(
        "{% for n in range(5) %}{{ n }}{% endfor %}", enable_async=True
    )

    async def _abandon_root():
        root = probe.root_render_func(probe.new_context())
        await root.__anext__()
        # deliberately no aclose(): a guaranteed leak on any tree

    with _w.catch_warnings(record=True) as rec:
        _w.simplefilter("always")
        _trio.run(_abandon_root)
        _gc.collect()
        _gc.collect()
    texts = [
        str(x.message)
        for x in rec
        if issubclass(x.category, ResourceWarning)
    ]
    ok = any(
        "garbage collected" in t and "<<template>>" in t for t in texts
    )
    return ok, f"probe saw {len(texts)} generator warnings ({texts[:2]})"


def exercise(run_async_fn, n=2):
    t = Template(
        "{% for item in range(300) %}[{{ item }}]{% endfor %}", enable_async=True
    )

    async def go():
        agen = t.generate_async()
        try:
            out = []
            for _ in range(n):
                try:
                    out.append(await agen.__anext__())
                except StopAsyncIteration:
                    break
            return "".join(out)
        finally:
            await agen.aclose()

    with warnings.catch_warnings(record=True) as w:
        warnings.simplefilter("always")
        out = run_async_fn(go)
        gc.collect()
        gc.collect()
    leaks = [
        str(x.message)
        for x in w
        if issubclass(x.category, ResourceWarning)
        and "generator" in str(x.message).lower()
    ]
    return out, leaks


def main():
    live, why = _leak_channel_live()
    if not live:
        print(
            f"FAIL: leak-detection channel is not live on this interpreter "
            f"({why}); refusing to score"
        )
        return 2
    expected_prefix = "[0"  # first two events: "[", then the first item
    for name, runner in (("asyncio", lambda f: asyncio.run(f())), ("trio", trio.run)):
        out, leaks = exercise(runner)
        print(f"h1[{name}]: out={out!r} leaks={len(leaks)}")
        if not out.startswith(expected_prefix):
            print(f"FAIL: unexpected prefix {out!r}")
            return 1
        if leaks:
            print("FAIL: leaked async generators (tree is not fixed):")
            for line in leaks:
                print("  " + line)
            return 1
    print("h1 OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())