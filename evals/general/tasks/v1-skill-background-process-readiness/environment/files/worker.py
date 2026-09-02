import time, json
time.sleep(0.6)
open('/tmp/worker_ready', 'w').write('ready')
time.sleep(1.2)
try:
    with open('/app/work_data.json') as f:
        data = json.load(f)
    val = sum(data['values'])
except Exception:
    val = -999999
open('/tmp/worker_result.txt', 'w').write(str(val))
