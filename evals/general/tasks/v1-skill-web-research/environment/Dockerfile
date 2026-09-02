FROM bench-base:python-3.12

WORKDIR /app

RUN cat > /app/report.html <<'EOF'
<!DOCTYPE html>
<html>
<head><title>Harbor Annual Report</title></head>
<body>
<h1>Harbor Annual Report</h1>
<p>Founded in 1998 by Ada Byte, Harbor publishes its metrics every year.</p>
<table>
<tr><th>Metric</th><th>Value</th></tr>
<tr><td>Revenue</td><td>1250</td></tr>
<tr><td>Founded</td><td>1998</td></tr>
<tr><td>Headquarters</td><td>Austin</td></tr>
<tr><td>Employees</td><td>340</td></tr>
</table>
</body>
</html>
EOF