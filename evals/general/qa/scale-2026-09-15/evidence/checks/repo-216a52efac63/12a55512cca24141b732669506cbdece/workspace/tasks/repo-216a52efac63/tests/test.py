import asyncio

import pytest
from jinja2 import Environment, StrictUndefined
from jinja2.exceptions import UndefinedError


def render(source, **values):
    return Environment(undefined=StrictUndefined).from_string(source).render(**values)


def test_map_explicit_none_is_a_real_fallback():
    assert render('{{ xs|map(attribute="name", default=None)|list }}', xs=[{}]) == "[None]"


def test_map_omitted_default_stays_undefined():
    assert render('{{ xs|map(attribute="name")|list }}', xs=[{}]) == "[Undefined]"


def test_map_non_none_default_and_present_values():
    source = '{{ xs|map(attribute="name", default="guest")|list }}'
    assert render(source, xs=[{}, {"name": "Ada"}]) == "['guest', 'Ada']"


def test_groupby_explicit_none_groups_missing_and_none():
    source = '{{ xs|groupby("name", default=None)|list }}'
    assert render(source, xs=[{}, {"name": "west"}, {"name": None}]) == (
        "[(None, [{}, {'name': None}]), ('west', [{'name': 'west'}])]"
    )


def test_groupby_omitted_default_retains_strict_undefined():
    with pytest.raises(UndefinedError):
        render('{{ xs|groupby("name")|list }}', xs=[{}, {}])


def test_async_groupby_explicit_none():
    async def run():
        env = Environment(enable_async=True, undefined=StrictUndefined)
        template = env.from_string('{{ xs|groupby("name", default=None)|list }}')
        return await template.render_async(xs=[{}, {"name": "west"}, {"name": None}])

    assert asyncio.run(run()) == "[(None, [{}, {'name': None}]), ('west', [{'name': 'west'}])]"
