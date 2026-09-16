# Preserve explicit `None` defaults in attribute filters

Modify `/app/jinja/src/jinja2/filters.py` in the pinned Jinja source tree.

The `map` and `groupby` filters accept a `default` keyword for missing
attributes. An omitted `default` must retain Jinja's current undefined-value
behavior, while an explicitly supplied `default=None` must be treated as a real
fallback value. Implement this consistently for both filters.

`groupby` must continue to support its existing synchronous and asynchronous
template paths. When an explicit `None` fallback is used, missing attributes
and attributes whose value is already `None` belong to the same group, and
grouping must remain deterministic alongside ordinary comparable values.

Preserve existing behavior for non-`None` defaults, present attributes, custom
undefined classes, and calls that omit `default`. Keep the change localized to
the filter implementation and maintain the repository's typing and style.

The deliverable is the updated `/app/jinja/src/jinja2/filters.py` file. Do not
add dependencies or modify the test harness.
