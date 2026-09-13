#!/usr/bin/env python3
"""Oracle fix for capstan-longshore: duckdb reports missing named parameters of
an EXECUTE in hash-map iteration order instead of declaration order.

The bug lives in PreparedStatement::MissingValuesException in
src/include/duckdb/main/prepared_statement.hpp. It collects the names of the
parameters that were not supplied into an `identifier_set_t` (an unordered
set), and then joins that set in its iteration order, which is hash-bucket
order -- unrelated to the order in which the parameters were declared.

Fix: collect (declaration index, name) pairs, then sort by declaration index
before joining. This is the same shape as the upstream fix: it keeps the
exact message text, only fixing the order.
"""

import sys

HEADER = "/app/src/src/include/duckdb/main/prepared_statement.hpp"

OLD_INCLUDES = '''#include "duckdb/common/identifier.hpp"
#include "duckdb/common/winapi.hpp"'''

NEW_INCLUDES = '''#include "duckdb/common/algorithm.hpp"
#include "duckdb/common/identifier.hpp"
#include "duckdb/common/pair.hpp"
#include "duckdb/common/winapi.hpp"'''

OLD_BODY = '''\t\t// Missing values
\t\tidentifier_set_t missing_set;
\t\tfor (auto &pair : parameters) {
\t\t\tauto &name = pair.first;
\t\t\tif (!values.count(name)) {
\t\t\t\tValue variable_value;
\t\t\t\tif (context && AllowsUserVariableFallback(name) &&
\t\t\t\t    ClientConfig::GetConfig(*context).GetUserVariable(name, variable_value)) {
\t\t\t\t\tcontinue;
\t\t\t\t}
\t\t\t\tmissing_set.insert(name);
\t\t\t}
\t\t}
\t\tvector<Identifier> missing_values;
\t\tfor (auto &val : missing_set) {
\t\t\tmissing_values.push_back(val);
\t\t}'''

NEW_BODY = '''\t\t// Missing values
\t\tvector<pair<idx_t, Identifier>> missing;
\t\tfor (auto &param_pair : parameters) {
\t\t\tauto &name = param_pair.first;
\t\t\tif (!values.count(name)) {
\t\t\t\tValue variable_value;
\t\t\t\tif (context && AllowsUserVariableFallback(name) &&
\t\t\t\t    ClientConfig::GetConfig(*context).GetUserVariable(name, variable_value)) {
\t\t\t\t\tcontinue;
\t\t\t\t}
\t\t\t\t// Remember the declaration index so the names can be reported in
\t\t\t\t// the order the parameters were declared, not hash-map order.
\t\t\t\tmissing.emplace_back(param_pair.second, name);
\t\t\t}
\t\t}
\t\t// Report missing parameters in declaration order, not hash-map iteration order.
\t\tstd::sort(missing.begin(), missing.end(),
\t\t          [](const pair<idx_t, Identifier> &a, const pair<idx_t, Identifier> &b) { return a.first < b.first; });
\t\tvector<Identifier> missing_values;
\t\tfor (auto &val : missing) {
\t\t\tmissing_values.push_back(val.second);
\t\t}'''


def patch(text: str) -> str:
    if NEW_BODY in text and NEW_INCLUDES in text:
        # Already fixed; idempotent.
        return text
    n = text.count(OLD_BODY)
    if n != 1:
        raise SystemExit(f"FATAL: expected exactly one instance of the buggy missing-values "
                         f"block in {HEADER}, found {n}")
    text = text.replace(OLD_BODY, NEW_BODY)
    n = text.count(OLD_INCLUDES)
    if n != 1:
        raise SystemExit(f"FATAL: expected exactly one instance of the include block, found {n}")
    text = text.replace(OLD_INCLUDES, NEW_INCLUDES)
    return text


def main() -> None:
    with open(HEADER, "r", encoding="utf-8") as fh:
        src = fh.read()
    patched = patch(src)
    with open(HEADER, "w", encoding="utf-8") as fh:
        fh.write(patched)
    print(f"patched {HEADER}")


if __name__ == "__main__":
    main()