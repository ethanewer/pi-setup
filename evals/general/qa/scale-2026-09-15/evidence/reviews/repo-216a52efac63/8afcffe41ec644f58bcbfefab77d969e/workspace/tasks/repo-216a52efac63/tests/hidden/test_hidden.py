import asyncio

from jinja2 import Environment


def test_explicit_empty_string_default_is_not_treated_as_missing():
    env = Environment()
    template = env.from_string('{{ xs|map(attribute="name", default="")|join("|") }}')
    assert template.render(xs=[{}, {"name": "A"}]) == "|A"


def test_groupby_none_with_case_insensitive_strings():
    env = Environment()
    source = '{{ xs|groupby("name", default=None)|list }}'
    assert env.from_string(source).render(
        xs=[{}, {"name": "West"}, {"name": "west"}, {"name": None}]
    ) == "[(None, [{}, {'name': None}]), ('West', [{'name': 'West'}, {'name': 'west'}])]"


def test_async_map_explicit_none():
    async def run():
        env = Environment(enable_async=True)
        template = env.from_string('{{ xs|map(attribute="name", default=None)|list }}')
        return await template.render_async(xs=[{}, {"name": "A"}])

    assert asyncio.run(run()) == "[None, 'A']"
