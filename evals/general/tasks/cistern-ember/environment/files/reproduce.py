#!/usr/bin/env python3
"""Reproducer for the async-template generator leak.

Streams a few templates in async mode, consumes their output incrementally
(as a real application streaming a page would) and then closes the stream
properly.  Some event-loop runtimes - notably trio - actively police
async-generator cleanup and report every generator that was abandoned before
it was exhausted.

When the tree is BUGGY this script prints the leaked 'Async generator ... was
garbage collected before it had been exhausted' ResourceWarnings under trio
(the asyncio runner hides them, because asyncio's shutdown_asyncgens closes
leftover generators silently) and exits 1.  When the tree is FIXED nothing
leaks and it exits 0.
"""

import asyncio
import gc
import sys
import warnings

import trio
from jinja2 import Environment
from jinja2 import DictLoader
from jinja2 import Template

ENV = Environment(
    loader=DictLoader(
        {
            "layout": (
                "{% block title %}{{ title }}{% endblock %}"
                "{% block body %}body{% endblock %}"
            ),
            "extended": "{% extends 'layout' %}{% block body %}"
            "{% for n in items %}<p>{{ n }}</p>{% endfor %}{% endblock %}",
            "bare_extend": "{% extends 'layout' %}",
        }
    ),
    enable_async=True,
)

SCENARIOS = [
    ("stream-loop", Template("{% for i in range(20) %}[{{ i }}]{% endfor %}", enable_async=True), {}),
    ("include-page", ENV.get_template("extended"), {"title": "Hello", "items": range(6)}),
    ("extend-page", ENV.get_template("bare_extend"), {"title": "Hello"}),
]


def consume_a_few(run_async_fn, tmpl, n, **ctx):
    """Consume n chunks of generate_async output, then close the stream."""

    async def go():
        agen = tmpl.generate_async(**ctx)
        try:
            chunks = []
            for _ in range(n):
                try:
                    chunks.append(await agen.__anext__())
                except StopAsyncIteration:
                    break
            return "".join(chunks)
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
    failed = 0
    for name, tmpl, ctx in SCENARIOS:
        for runner_name, runner in (
            ("asyncio", lambda f: asyncio.run(f())),
            ("trio", trio.run),
        ):
            out, leaks = consume_a_few(runner, tmpl, 2, **ctx)
            print(f"[{name}/{runner_name}] first chunks={out!r} leaked={len(leaks)}")
            for leak in leaks:
                print("    " + leak)
            if leaks:
                failed += 1

    if failed:
        print(
            "RESULT: leaked async generators detected while streaming template "
            "output incrementally - the bug reproduces (exit 1)."
        )
        return 1
    print(
        "RESULT: no leaked async generators after incremental consumption "
        "with proper cleanup - the tree is fixed (exit 0)."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())