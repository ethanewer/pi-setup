#!/usr/bin/env python3
"""Reproduce the RAW_URI defect in falcon.testing.

A request environment built by falcon.testing.create_environ() must report
the raw (still percent-encoded) request path in the WSGI environ variable
RAW_URI, exactly as real WSGI servers (wsgiref, gunicorn, uWSGI) do, while
PATH_INFO carries the decoded path. Before the defect is fixed, RAW_URI is
always '/' no matter which path was requested.

Exit status: 0 when the behaviour is correct; 1 when the defect is present.
Prints the observed RAW_URI and PATH_INFO so a human (or the verifier) can
see which side of the contract failed.
"""
import sys

import falcon.testing as testing

# An encoded slash inside a path segment: the raw form must survive in
# RAW_URI while PATH_INFO must carry the decoded form.
RAW = '/cache/http%3A%2F%2Ffalconframework.org/status'
DECODED = '/cache/http://falconframework.org/status'


def main():
    env = testing.create_environ(path=RAW)
    raw_uri = env.get('RAW_URI')
    path_info = env.get('PATH_INFO')

    print('RAW_URI  =', repr(raw_uri))
    print('PATH_INFO=', repr(path_info))

    if raw_uri != RAW:
        print('DEFECT PRESENT: RAW_URI does not carry the raw request path.')
        return 1
    if path_info != DECODED:
        print('REGRESSION: PATH_INFO no longer carries the decoded path.')
        return 1
    print('behaviour correct: RAW_URI is the raw request path, PATH_INFO is decoded')
    return 0


if __name__ == '__main__':
    sys.exit(main())