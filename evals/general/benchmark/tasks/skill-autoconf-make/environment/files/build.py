import os
HERE = os.path.dirname(os.path.abspath(__file__))
version = "unknown"
with open(os.path.join(HERE, 'config.mk')) as f:
    for line in f:
        line = line.strip()
        if line.startswith('VERSION'):
            version = line.split('=', 1)[1].strip()
os.makedirs(os.path.join(HERE, 'built'), exist_ok=True)
with open(os.path.join(HERE, 'built', 'output.txt'), 'w') as out:
    out.write("APP_VERSION=%s\n" % version)