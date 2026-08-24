# Service Health Monitor with Auto-Restart

You are a system administrator tasked with implementing a service health monitoring system for a critical application. The application runs as a user-space service but has been experiencing intermittent failures. Your task is to create a robust monitoring and auto-restart script.

## Your Task

Create a bash script `/app/service-monitor.sh` that implements the following functionality:

### 1. Configuration Parsing
Read the configuration file `/app/service.conf` which contains:
- `SERVICE_NAME`: Name of the service to monitor
- `SERVICE_CMD`: Command to start the service (quotes allowed for arguments)
- `CHECK_PORT`: TCP port to check for service responsiveness (or 0 for no port check)
- `CHECK_INTERVAL`: Seconds between health checks (5-300)
- `MAX_RESTARTS`: Maximum restart attempts before giving up (1-10)
- `LOG_FILE`: Path for monitoring logs

The configuration file format is key=value (one per line). Comments start with #.

### 2. Service Management
The script must:
- Parse and validate the configuration
- Start the initial service instance
- Monitor it continuously with the specified CHECK_INTERVAL
- Perform health checks using both:
  a) Process status check (pid exists and process is running)
  b) Network check (if CHECK_PORT > 0, verify service listens on port)
- Restart failed services up to MAX_RESTARTS times
- Log all actions to LOG_FILE with timestamps

### 3. Health Check Implementation
For each health check interval:
1. Verify the service process is still running (by pid)
2. If CHECK_PORT > 0, verify the service is listening on that port using `netstat` or `ss`
3. If either check fails, restart the service
4. Log each restart with attempt number and reason

### 4. Clean Shutdown
When the script receives SIGTERM or SIGINT:
1. Gracefully stop the monitored service
2. Log shutdown event
3. Exit cleanly

### 5. Output Requirements
The script must create and maintain:
1. `/app/monitor-status.json` - Current status in JSON format:
```json
{
  "service_name": "example-service",
  "pid": 1234,
  "status": "running|restarting|failed",
  "restart_count": 0,
  "last_check": "2024-01-15T10:30:00Z",
  "uptime_seconds": 3600
}
```
(Update this file after each health check)

2. LOG_FILE as specified in config - Human-readable logs with timestamps

3. `/app/restart-summary.txt` - Created when monitoring stops (normal or due to failures), containing:
   - Total runtime of monitor script
   - Total restart attempts
   - Final status (normal_shutdown|max_restarts_exceeded)
   - Any error messages from failed startups

## Expected Outputs
- `/app/service-monitor.sh` - Executable bash script
- `/app/monitor-status.json` - JSON status file (created/updated by script)
- LOG_FILE (as specified in config) - Monitoring logs
- `/app/restart-summary.txt` - Final summary (created when script exits)

## Test Expectations
Tests will:
1. Verify all output files exist with correct formats
2. Start your script with a test configuration
3. Simulate service failures by killing the process
4. Verify automatic restarts occur and are logged
5. Verify clean shutdown on SIGTERM
6. Check JSON status file is updated correctly
7. Validate restart summary contains correct counts

Your script must handle edge cases: invalid config values, service fails to start, port already in use, etc.