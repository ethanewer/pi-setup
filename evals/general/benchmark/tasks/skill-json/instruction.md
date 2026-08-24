# JSON parsing

`/app/config.json` is a valid JSON file with a nested structure.

Parse the JSON and extract the value stored at the nested key `server.port` (i.e. the `port` field inside the `server` object). Write that value as a plain decimal string to `/app/port_output.txt`, ending with a newline.

Example (not the real file):

```json
{"server": {"host": "db.internal", "port": 5432}}
```

for which the answer would be `5432`.

Implementation hint:

```python
import json
cfg = json.load(open('/app/config.json'))
port = cfg['server']['port']
open('/app/port_output.txt', 'w').write(str(port) + '\n')
```

Afterward `/app/port_output.txt` must exist and contain exactly the integer port number from the JSON.