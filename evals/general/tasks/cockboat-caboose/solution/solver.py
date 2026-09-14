#!/usr/bin/env python3
"""Apply the upstream fix for the valueless Content-Type parameter crash to

    /app/src/src/requests/utils.py

The buggy parser stores a parameter without an '=' as a boolean True
placeholder; code that later resolves the response encoding calls .strip() on
it and dies with AttributeError. The fix only records parameters that contain
an '='. This is the same single-function change the upstream fix commit made.

Fails loudly if the working tree does not contain exactly the expected buggy
function body (the image is pinned to the parent commit, so it must).
"""
import pathlib
import sys

UTILS = pathlib.Path("/app/src/src/requests/utils.py")

OLD = '''def _parse_content_type_header(header):
    """Returns content type and parameters from given header

    :param header: string
    :return: tuple containing content type and dictionary of
         parameters
    """

    tokens = header.split(";")
    content_type, params = tokens[0].strip(), tokens[1:]
    params_dict = {}
    items_to_strip = "\\"' "

    for param in params:
        param = param.strip()
        if param:
            key, value = param, True
            index_of_equals = param.find("=")
            if index_of_equals != -1:
                key = param[:index_of_equals].strip(items_to_strip)
                value = param[index_of_equals + 1 :].strip(items_to_strip)
            params_dict[key.lower()] = value
    return content_type, params_dict'''

NEW = '''def _parse_content_type_header(header):
    """Returns content type and parameters from given header.

    :param header: string
    :return: tuple containing content type and dictionary of
         parameters.
    """

    tokens = header.split(";")
    content_type, params = tokens[0].strip(), tokens[1:]
    params_dict = {}
    strip_chars = "\\"' "

    for param in params:
        param = param.strip()
        if param and (idx := param.find("=")) != -1:
            key = param[:idx].strip(strip_chars)
            value = param[idx + 1 :].strip(strip_chars)
            params_dict[key.lower()] = value
    return content_type, params_dict'''


def main() -> int:
    src = UTILS.read_text()
    if NEW in src:
        print("fix already present; nothing to do")
        return 0
    if OLD not in src:
        print(
            "ERROR: could not locate the buggy _parse_content_type_header body "
            "in " + str(UTILS),
            file=sys.stderr,
        )
        return 1
    UTILS.write_text(src.replace(OLD, NEW, 1))
    print("applied upstream fix to _parse_content_type_header")
    return 0


if __name__ == "__main__":
    sys.exit(main())