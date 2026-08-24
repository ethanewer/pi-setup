# Network Service Monitor and Health Check System

## Your Task

You are setting up a monitoring system for critical network services. The system must check multiple services, validate their health, and produce a comprehensive status report.

You have been provided with a service configuration file at `/app/services.conf` that defines various network services to monitor. Each service has specific check requirements.

### 1. Parse Service Configuration
Read `/app/services.conf` which contains service definitions in this format:
```
[service_name]
type = [http|tcp|dns]
host = [hostname_or_ip]
port = [port_number]
path = [optional_path_for_http]
interval = [check_interval_seconds]
timeout = [timeout_seconds]
```

Example:
```
[web_api]
type = http
host = api.example.com
port = 8080
path = /health
interval = 30
timeout = 5

[database]
type = tcp
host = 192.168.1.100
port = 5432
interval = 60
timeout = 3
```

### 2. Create Monitoring Script
Write a Python script `/app/monitor.py` that:
- Parses the configuration file using Python's configparser
- For each service, performs appropriate health checks based on type:
  - **HTTP**: Send GET request to `http://host:port/path`, check for 200 OK
  - **TCP**: Attempt TCP connection to `host:port`, verify connection succeeds
  - **DNS**: Resolve `host` to IP addresses, verify at least one resolution succeeds
- Implements proper error handling (connection refused, timeouts, etc.)
- Logs all checks to `/app/monitoring.log` with timestamp, service name, and status
- Generates a summary report at `/app/status_report.json`

### 3. Generate Status Report
Create `/app/status_report.json` with this exact structure:
```json
{
  "timestamp": "2024-01-01T12:00:00Z",
  "total_services": 5,
  "healthy_services": 3,
  "unhealthy_services": 2,
  "health_percentage": 60.0,
  "services": [
    {
      "name": "web_api",
      "type": "http",
      "host": "api.example.com",
      "port": 8080,
      "status": "healthy",
      "response_time": 0.125,
      "last_check": "2024-01-01T12:00:00Z",
      "error": null
    }
  ]
}
```

### 4. Create Systemd Service Unit
Create a systemd service unit file at `/etc/systemd/system/network-monitor.service` with:
- Description: "Network Service Monitor"
- Type: simple
- Restart: on-failure
- RestartSec: 10
- ExecStart: `/usr/bin/python3 /app/monitor.py`
- StandardOutput: append to `/app/monitoring.log`
- StandardError: append to `/app/monitoring.log`

### 5. Set Up Cron Job
Create a cron job entry in `/etc/cron.d/network-monitor` that runs the monitor every 5 minutes and:
- Redirects output to `/app/cron.log`
- Includes timestamp in cron output
- Only runs if the systemd service is not active

## Requirements

1. Your script must handle all edge cases gracefully:
   - Invalid configuration sections
   - Missing required fields
   - Network timeouts
   - DNS resolution failures

2. The systemd service must have correct permissions:
   - User: root
   - Group: root
   - File permissions: 644

3. The cron entry must use the full path to python3

4. All output files must be created with appropriate permissions

## Expected Outputs

The tests will verify:
- `/app/monitor.py` exists and is executable (chmod +x)
- `/app/status_report.json` exists with valid JSON structure
- `/app/monitoring.log` exists and contains log entries
- `/etc/systemd/system/network-monitor.service` exists with correct content
- `/etc/cron.d/network-monitor` exists with correct cron syntax
- The JSON report has all required fields with correct data types
- The health percentage is calculated correctly (healthy/total * 100)

The agent should not start the systemd service (just create the file), but the cron job should be testable by checking the file syntax.