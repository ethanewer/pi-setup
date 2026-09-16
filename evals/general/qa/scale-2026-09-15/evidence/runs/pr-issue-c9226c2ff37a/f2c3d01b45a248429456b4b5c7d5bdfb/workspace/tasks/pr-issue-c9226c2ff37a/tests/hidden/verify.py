import httpx


def check(actual, expected):
    assert str(actual.url) == expected, (str(actual.url), expected)


check(
    httpx.Request("GET", "https://example.com/items?old=1", params={}),
    "https://example.com/items",
)
check(
    httpx.Request("GET", "https://example.com/items?old=1", params={"new": "2"}),
    "https://example.com/items?new=2",
)
check(
    httpx.Request(
        "GET",
        "https://example.com/items?old=1",
        params=[("tag", "a b"), ("tag", ""), ("x&y", "q/r")],
    ),
    "https://example.com/items?tag=a%20b&tag=&x%26y=q%2Fr",
)
check(
    httpx.Request("GET", "https://example.com/items?old=1"),
    "https://example.com/items?old=1",
)
check(
    httpx.Request("GET", "https://example.com/items", params=[("a", "1"), ("b", "2")]),
    "https://example.com/items?a=1&b=2",
)
