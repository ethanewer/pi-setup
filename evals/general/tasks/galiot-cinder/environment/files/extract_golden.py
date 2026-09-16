"""Build-time extraction of the upstream regression test for galiot-cinder.

Reads /tmp/tt_testing.py (tests/test_testing.py at the FIX commit, produced
by `git show <fix-sha>:tests/test_testing.py` in the Dockerfile), slices out
the verbatim test_create_environ_preserve_raw_uri function and writes
/opt/golden/test_preserve_raw_uri.py. The sha256 of the produced file is
asserted against the constant the verifier uses, so the image fails closed if
the extraction ever drifts. The fix commit is fetched only into a throwaway
bare clone that is deleted; it never enters the working clone the agent gets.
"""
import hashlib
import os

EXPECTED_SHA = '154850aeee62e41efe6802cd8f7bab214a39d5b2b98c80e0c7b372d9b93213e8'
FIX_SHA = '69cdcd6edd2ee33f4ac9f7793e1cc3c4f99da692'


def main() -> None:
    src = open('/tmp/tt_testing.py').read()
    marker = 'def test_create_environ_preserve_raw_uri():'
    start = src.index(marker)
    end = src.index('\ndef ', start)
    fn = src[start:end].rstrip('\n') + '\n'
    content = ('# falconry/falcon tests/test_testing.py: verbatim regression test for the\n'
               '# RAW_URI defect, extracted from fix commit '
               + FIX_SHA + '.\n'
               'import falcon.testing as testing\n\n\n' + fn + '\n')
    os.makedirs('/opt/golden', exist_ok=True)
    out = '/opt/golden/test_preserve_raw_uri.py'
    open(out, 'w').write(content)

    sha = hashlib.sha256(content.encode()).hexdigest()
    print('golden sha256:', sha)
    if sha != EXPECTED_SHA:
        raise SystemExit('sha mismatch: %s != %s' % (sha, EXPECTED_SHA))
    assert 'def test_create_environ_preserve_raw_uri' in content
    assert 'RAW_URI' in content
    print('wrote', out, len(content), 'bytes')


if __name__ == '__main__':
    main()