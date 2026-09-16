"""Apply the upstream fix for the RAW_URI defect to a falcon checkout.

The defect: falcon/testing/helpers.py create_environ() hardcodes the WSGI
environ variable RAW_URI to '/' regardless of the requested path. The fix
captures the original path before percent-decoding and reports that as
RAW_URI, leaving the %-decoded path in PATH_INFO (the ISO-8859-1 tunnelling
of decoded UTF-8 is untouched). This mirrors the upstream fix for
falconry/falcon issue #2157 (commit 69cdcd6edd2ee33f4ac9f7793e1cc3c4f99da692).

Usage: python3 fix_helpers.py <path-to-falcon-checkout>
"""
import sys


def main(repo: str) -> None:
    src = repo.rstrip('/') + '/falcon/testing/helpers.py'
    code = open(src).read()

    old_decode = (
        "    # NOTE(kgriffs): wsgiref, gunicorn, and uWSGI all unescape\n"
        "    # the paths before setting PATH_INFO\n"
        "    path = uri.decode(path, unquote_plus=False)\n"
    )
    new_decode = (
        "    # NOTE(kgriffs): wsgiref, gunicorn, and uWSGI all unescape\n"
        "    # the paths before setting PATH_INFO but preserve raw original\n"
        "    raw_path = path\n"
        "    path = uri.decode(path, unquote_plus=False)\n"
    )
    old_env = "        'RAW_URI': '/',"
    new_env = "        'RAW_URI': raw_path,"

    if old_decode not in code:
        raise SystemExit('decode block not found in helpers.py; tree not at parent?')
    if old_env not in code:
        raise SystemExit('RAW_URI hardcode not found in helpers.py; already fixed?')
    code = code.replace(old_decode, new_decode)
    code = code.replace(old_env, new_env)
    open(src, 'w').write(code)
    print('fix applied to', src)


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('usage: fix_helpers.py <checkout>')
    main(sys.argv[1])