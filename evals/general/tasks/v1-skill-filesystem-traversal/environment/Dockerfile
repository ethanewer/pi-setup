FROM bench-base:python-3.12
WORKDIR /app
RUN python3 - <<'PYEOF'
import os
root = '/app/tree'
os.makedirs(root + '/sub1/sub2', exist_ok=True)
os.makedirs(root + '/sub1/empty', exist_ok=True)
os.makedirs(root + '/sub3', exist_ok=True)
open(root + '/a.txt', 'w').write('a' * 10)
open(root + '/sub1/b.log', 'w').write('b' * 20)
open(root + '/sub1/sub2/c.txt', 'w').write('c' * 30)
open(root + '/sub1/sub2/d.log', 'w').write('d' * 40)
open(root + '/sub3/e.csv', 'w').write('e' * 50)
PYEOF