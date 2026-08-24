# Custom Service Orchestration and Health Monitoring System

You are tasked with building a system administration tool that orchestrates multiple services and monitors their health. This task requires parsing configuration files, managing service processes, setting up automated monitoring, and generating health reports.

## Background

A development team needs a simple service orchestration system that can:
1. Start multiple services from configuration
2. Monitor their availability and resource usage
3. Automatically restart failed services
4. Generate periodic health reports

You'll work with two configuration files:
- `/app/services.conf`: Defines services to manage
- `/app/monitoring.conf`: Defines monitoring parameters

## Your Task

Implement a Python script `/app/service_orchestrator.py` that performs the following:

### 1. Parse Configuration Files
- Read `/app/services.conf` (INI format) containing service definitions
- Read `/app/monitoring.conf` (JSON format) containing monitoring settings
- Validate that all required fields are present in both files

### 2. Service Management Functions
Implement these functions in your script:
- `start_services()`: Start all services defined in the configuration
- `stop_services()`: Gracefully stop all running services  
- `check_service_health()`: Check if each service is responsive
- `restart_failed_services()`: Restart any services that are not responding

### 3. Health Monitoring Loop
Create a monitoring loop that:
- Runs continuously (use the interval from monitoring.conf)
- Checks service health status
- Attempts to restart any failed service (up to max_retries from config)
- Logs all actions to `/app/service_log.txt` with timestamps
- Generates a health report every 5 cycles

### 4. Health Report Generation
Every 5 monitoring cycles, generate a JSON report at `/app/health_report.json` containing:
- `timestamp`: ISO format timestamp of report generation
- `total_services`: Total number of services configured
- `running_services`: Number of services currently running
- `failed_services`: Array of service names that are failed
- `service_details`: Object mapping service names to objects with:
  - `status`: "running" or "failed"
  - `pid`: Process ID (if running)
  - `uptime`: Seconds since start (if running)
  - `restart_count`: Number of times restarted
- `system_load`: Current system load average (1-minute)

### 5. Signal Handling
Implement graceful shutdown on SIGTERM:
- Stop all services
- Write final status to `/app/shutdown_report.json`
- Exit cleanly

## Mock Services for Testing

Since we can't run real services in this environment, implement mock services as subprocesses that:
1. Write their PID to `/tmp/mock_service_<name>.pid`
2. Respond to health checks by writing "ALIVE" to a named pipe
3. Can be killed with SIGTERM

You'll find starter mock service scripts at:
- `/app/mock_web_server.py` (listens on port 8080)
- `/app/mock_database.py` (listens on port 5432)
- `/app/mock_cache.py` (listens on port 6379)

## Expected Outputs

Your script must create:
1. `/app/service_log.txt`: Log file with all monitoring actions
2. `/app/health_report.json`: Periodic health reports (every 5 cycles)
3. `/app/shutdown_report.json`: Final status when script is terminated

## Test Verification

The tests will:
1. Start your orchestrator script
2. Verify services are running
3. Simulate a service failure
4. Verify automatic restart occurs
5. Check health reports are generated
6. Send SIGTERM and verify graceful shutdown

## Configuration File Formats

### /app/services.conf (INI format)
```
[web_server]
command = python3 /app/mock_web_server.py
port = 8080
health_check = http://localhost:8080/health

[database]
command = python3 /app/mock_database.py  
port = 5432
health_check = nc -z localhost 5432

[cache]
command = python3 /app/mock_cache.py
port = 6379
health_check = nc -z localhost 6379
```

### /app/monitoring.conf (JSON format)
```
{
  "monitoring_interval": 10,
  "max_retries": 3,
  "health_check_timeout": 5,
  "log_level": "INFO"
}
```

## Constraints

- Use only standard library modules (subprocess, signal, json, configparser, etc.)
- Handle edge cases (missing configs, permission errors, etc.)
- Ensure no zombie processes remain after shutdown
- Log all actions with timestamps in ISO format
- Health reports must be valid JSON

## Hints

1. Use `subprocess.Popen` to start services with `start_new_session=True`
2. Track PIDs to manage service processes
3. Use `os.kill` with signal 0 to check if process exists
4. Implement exponential backoff for restart attempts
5. Use `signal.signal()` to handle SIGTERM gracefully