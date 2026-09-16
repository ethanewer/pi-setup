#!/bin/bash
# Oracle for cistern-ember. Repairs the jinja2 tree in /app/src by applying
# the exact hunks of the upstream fix for the missing-aclose bug (the same
# change that upstream shipped; the patched modules become byte-identical to
# the fixed upstream files), writes /app/diagnosis.md, and proves the repair
# with the project's own test suite and the reproducer. Reads nothing under
# /tests and never references it.
set -u

cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

python3 - <<'PY'
import pathlib

root = pathlib.Path("/app/src")
BASE = root / "src" / "jinja2"

def replace(path, old, new, count=1):
    src = path.read_text()
    n = src.count(old)
    if n != count:
        raise SystemExit(
            f"oracle: {path}: expected {count} occurrence(s) of snippet, found {n}"
        )
    path.write_text(src.replace(old, new))
    print(f"oracle: patched {path}")

# -- src/jinja2/async_utils.py: auto_aiter becomes a plain function that
#    never creates an async-generator layer of its own. -----------------------
f = BASE / "async_utils.py"
old = (
    'async def auto_aiter(\n'
    '    iterable: "t.Union[t.AsyncIterable[V], t.Iterable[V]]",\n'
    ') -> "t.AsyncIterator[V]":\n'
    '    if hasattr(iterable, "__aiter__"):\n'
    '        async for item in t.cast("t.AsyncIterable[V]", iterable):\n'
    '            yield item\n'
    '    else:\n'
    '        for item in iterable:\n'
    '            yield item\n'
)
new = (
    'class _IteratorToAsyncIterator(t.Generic[V]):\n'
    '    def __init__(self, iterator: "t.Iterator[V]"):\n'
    '        self._iterator = iterator\n'
    '\n'
    '    def __aiter__(self) -> "te.Self":\n'
    '        return self\n'
    '\n'
    '    async def __anext__(self) -> V:\n'
    '        try:\n'
    '            return next(self._iterator)\n'
    '        except StopIteration as e:\n'
    '            raise StopAsyncIteration(e.value) from e\n'
    '\n'
    '\n'
    'def auto_aiter(\n'
    '    iterable: "t.Union[t.AsyncIterable[V], t.Iterable[V]]",\n'
    ') -> "t.AsyncIterator[V]":\n'
    '    if hasattr(iterable, "__aiter__"):\n'
    '        return iterable.__aiter__()\n'
    '    else:\n'
    '        return _IteratorToAsyncIterator(iter(iterable))\n'
)
replace(f, old, new)
src = f.read_text()
if "if t.TYPE_CHECKING:" not in src:
    f.write_text(
        src.replace(
            'V = t.TypeVar("V")\n',
            'if t.TYPE_CHECKING:\n    import typing_extensions as te\n\nV = t.TypeVar("V")\n',
            1,
        )
    )
    print(f"oracle: patched {f} (typing_extensions import)")

# -- src/jinja2/environment.py: generate_async closes the render generator. --
f = BASE / "environment.py"
old = (
    "        try:\n"
    '            async for event in self.root_render_func(ctx):  # type: ignore\n'
    "                yield event\n"
    "        except Exception:\n"
)
new = (
    "        try:\n"
    "            agen = self.root_render_func(ctx)\n"
    "            try:\n"
    '                async for event in agen:  # type: ignore\n'
    "                    yield event\n"
    "            finally:\n"
    "                # we can't use async with aclosing(...) because that's only\n"
    "                # in 3.10+\n"
    "                await agen.aclose()  # type: ignore\n"
    "        except Exception:\n"
)
replace(f, old, new)
src = f.read_text()
f.write_text(
    src.replace(
        "    ) -> t.AsyncIterator[str]:",
        "    ) -> t.AsyncGenerator[str, object]:",
        1,
    )
)
print(f"oracle: patched {f} (return type)")

# -- src/jinja2/compiler.py: compiled extends / block-call / include code
#    closes the nested render generators in a finally. ------------------------
f = BASE / "compiler.py"
old = (
    "            else:\n"
    "                self.writeline(\n"
    '                    "async for event in parent_template.root_render_func(context):"\n'
    "                )\n"
    "                self.indent()\n"
    '                self.writeline("yield event")\n'
    "                self.outdent()\n"
)
new = (
    "            else:\n"
    '                self.writeline("agen = parent_template.root_render_func(context)")\n'
    '                self.writeline("try:")\n'
    "                self.indent()\n"
    '                self.writeline("async for event in agen:")\n'
    "                self.indent()\n"
    '                self.writeline("yield event")\n'
    "                self.outdent()\n"
    "                self.outdent()\n"
    '                self.writeline("finally: await agen.aclose()")\n'
)
replace(f, old, new)

old = (
    "        else:\n"
    "            self.writeline(\n"
    '                f"{self.choose_async()}for event in"\n'
    '                f" context.blocks[{node.name!r}][0]({context}):",\n'
    "                node,\n"
    "            )\n"
    "            self.indent()\n"
    '            self.simple_write("event", frame)\n'
    "            self.outdent()\n"
)
new = (
    "        else:\n"
    '            self.writeline(f"gen = context.blocks[{node.name!r}][0]({context})")\n'
    '            self.writeline("try:")\n'
    "            self.indent()\n"
    "            self.writeline(\n"
    '                f"{self.choose_async()}for event in gen:",\n'
    "                node,\n"
    "            )\n"
    "            self.indent()\n"
    '            self.simple_write("event", frame)\n'
    "            self.outdent()\n"
    "            self.outdent()\n"
    "            self.writeline(\n"
    '                f"finally: {self.choose_async(\'await gen.aclose()\', \'gen.close()\')}"\n'
    "            )\n"
)
replace(f, old, new)

old = (
    "        skip_event_yield = False\n"
    "        if node.with_context:\n"
    "            self.writeline(\n"
    '                f"{self.choose_async()}for event in template.root_render_func("\n'
    '                "template.new_context(context.get_all(), True,"\n'
    '                f" {self.dump_local_context(frame)})):"\n'
    "            )\n"
    "        elif self.environment.is_async:\n"
    "            self.writeline(\n"
    '                "for event in (await template._get_default_module_async())"\n'
    '                "._body_stream:"\n'
    "            )\n"
    "        else:\n"
    '            self.writeline("yield from template._get_default_module()._body_stream")\n'
    "            skip_event_yield = True\n"
    "\n"
    "        if not skip_event_yield:\n"
    "            self.indent()\n"
    '            self.simple_write("event", frame)\n'
    "            self.outdent()\n"
)
new = (
    "        def loop_body() -> None:\n"
    "            self.indent()\n"
    '            self.simple_write("event", frame)\n'
    "            self.outdent()\n"
    "\n"
    "        if node.with_context:\n"
    "            self.writeline(\n"
    '                f"gen = template.root_render_func("\n'
    '                "template.new_context(context.get_all(), True,"\n'
    '                f" {self.dump_local_context(frame)}))"\n'
    "            )\n"
    '            self.writeline("try:")\n'
    "            self.indent()\n"
    '            self.writeline(f"{self.choose_async()}for event in gen:")\n'
    "            loop_body()\n"
    "            self.outdent()\n"
    "            self.writeline(\n"
    '                f"finally: {self.choose_async(\'await gen.aclose()\', \'gen.close()\')}"\n'
    "            )\n"
    "        elif self.environment.is_async:\n"
    "            self.writeline(\n"
    '                "for event in (await template._get_default_module_async())"\n'
    '                "._body_stream:"\n'
    "            )\n"
    "            loop_body()\n"
    "        else:\n"
    '            self.writeline("yield from template._get_default_module()._body_stream")\n'
)
replace(f, old, new)

print("oracle: all three modules patched")
PY
status=$?
if [ $status -ne 0 ]; then
    echo "oracle: source patch failed" >&2
    exit $status
fi

cat > /app/diagnosis.md <<'MD'
## Diagnosis: unclosed async generators when streaming template output

### Area
The async rendering path of the engine: `Template.generate_async` in
`src/jinja2/environment.py` together with the code the compiler
(`src/jinja2/compiler.py`) emits for templates that yield from nested render
generators (`{% extends %}` parent templates, `{% include %}`d templates,
`self.foo()` block calls), and the async-iterator adapter `auto_aiter` in
`src/jinja2/async_utils.py`.

### Root cause
`auto_aiter` was itself an async-generator function, and the compiled code /
`generate_async` iterated the nested render generators with a bare
`async for` that never closed them. When a consumer stopped reading early
(streaming a page, partial consumption after include/extends/block calls),
the underlying generators were abandoned; GC-then-report runtimes like trio
then emitted `ResourceWarning: Async generator ... was garbage collected
before it had been exhausted`. asyncio hides the leak by silently closing
leftover generators at shutdown, which is why it needed a strict runtime to
surface.

### Fix
- `auto_aiter` is now a plain function: for async iterables it returns
  `iterable.__aiter__()` and for sync iterables a tiny
  `_IteratorToAsyncIterator` wrapper, so no extra generator layer leaks.
- `generate_async` and the compiled `extends` / `include` / block-call code
  wrap their `async for` in `try/finally` that awaits `agen.aclose()` (+
  `gen.close()` in sync mode for block calls), so nested template render
  generators are closed as soon as the consumer stops or closes the stream.

### Verification
`PYTHONPATH=/app/src/src python3 /app/reproduce.py` exits 0 (no leaks under
asyncio or trio) and the project's own suite,
`PYTHONPATH=/app/src/src python3 -m pytest -q tests/`, passes in full.
MD

# Sanity-check the repair with the project's own machinery.
echo "oracle: running /app/reproduce.py"
PYTHONPATH=/app/src/src python3 /app/reproduce.py
r1=$?
echo "oracle: running the project's own test suite"
PYTHONPATH=/app/src/src python3 -m pytest -q tests/ -p no:cacheprovider > /tmp/oracle_pytest.log 2>&1
r2=$?
tail -1 /tmp/oracle_pytest.log
echo "oracle: reproduce exit=$r1 pytest exit=$r2"
if [ $r1 -ne 0 ] || [ $r2 -ne 0 ]; then
    echo "oracle: sanity checks failed" >&2
    exit 1
fi
exit 0