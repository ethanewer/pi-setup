import spect


def test_simple():
    assert spect.prefix_digest('ab') == '00c3'


def test_whitespace_ignored():
    assert spect.prefix_digest('a b') == '00c3'
    assert spect.prefix_digest('ab') == '00c3'


def test_empty():
    assert spect.prefix_digest('   ') == 'EMPTY'


def test_numeric_spacing():
    assert spect.prefix_digest('1 2 3 ') == '0096'


def test_single_ascii():
    assert spect.prefix_digest('x') == '0078'