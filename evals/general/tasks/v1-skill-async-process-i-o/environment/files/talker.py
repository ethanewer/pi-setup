import sys
import time

tag = sys.argv[1] if len(sys.argv) > 1 else "nobody"
time.sleep(0.6)
print("hello from %s" % tag, flush=True)