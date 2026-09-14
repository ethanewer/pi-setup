"""Build-time smoke for galiot-cinder.

Runs inside the task image build, from /app/src. Proves the shipped tree
still exhibits the defect the task is about: falcon.testing.create_environ()
reports RAW_URI as '/' no matter which path was requested, while PATH_INFO is
correctly percent-decoded (real WSGI servers expose the raw path in RAW_URI).
This must hold inside THIS image, with ITS dependency pins; if the bug does
not reproduce here, the oracle cannot pass and the image must fail closed.
"""
from falcon import testing

# The exact mined reproduction: an encoded slash inside a path segment.
path = '/cache/http%3A%2F%2Ffalconframework.org/status'
env = testing.create_environ(path=path)

assert env['PATH_INFO'] == '/cache/http://falconframework.org/status', env['PATH_INFO']
assert env['RAW_URI'] == '/', env['RAW_URI']  # the shipped tree must still be buggy

# A second, different input for good measure.
assert testing.create_environ(path='/x%2Fy')['RAW_URI'] == '/'
print('parent tree reproduces the RAW_URI defect in this image')