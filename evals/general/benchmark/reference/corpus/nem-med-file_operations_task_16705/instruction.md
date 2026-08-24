# Log Analysis and Report Generation Task

You are tasked with creating a log processing system that analyzes application logs, extracts key metrics, and generates structured reports. This task requires file operations, data parsing, and aggregation skills.

## Input Data Structure

The system has two input sources:

1. **Configuration file** (`/app/config.json`):
```json
{
  "log_directory": "/app/logs",
  "output_directory": "/app/reports",
  "log_pattern": "app_*.log",
  "time_range": {
    "start": "2024-01-15 00:00:00",
    "end": "2024-01-15 23:59:59"
  },
  "severity_levels": ["ERROR", "WARNING", "INFO"],
  "max_file_size_mb": 10
}
```

2. **Log files** (in `/app/logs/` directory):
- Multiple files matching `app_*.log` pattern
- Each line format: `TIMESTAMP | SEVERITY | COMPONENT | MESSAGE | USER_ID`
- Example: `2024-01-15 14:30:22 | ERROR | Database | Connection timeout | user123`

## Your Task

1. **Validate and Setup**
   - Read the configuration from `/app/config.json`
   - Verify the log directory exists and contains at least one matching log file
   - Create the output directory if it doesn't exist
   - Check that no single log file exceeds `max_file_size_mb` (skip oversized files with warning)

2. **Process Log Files**
   - Read all log files matching the pattern in the specified directory
   - Filter logs within the `time_range` (inclusive)
   - Only include logs with severity levels listed in `severity_levels`
   - Handle malformed lines by logging errors to `/app/reports/errors.txt` with the line number and file

3. **Generate Analysis**
   For the filtered logs, calculate:
   - Total count of logs by severity level
   - Top 5 most frequent error messages (case-insensitive grouping)
   - Hourly distribution of logs (count per hour of day)
   - Component-wise breakdown (count by component)

4. **Create Output Reports**
   - **CSV Report** (`/app/reports/log_summary.csv`): Hourly distribution with columns: `hour`, `error_count`, `warning_count`, `info_count`, `total`
   - **JSON Report** (`/app/reports/analysis.json`): Structured data with keys:
     ```json
     {
       "metadata": {
         "files_processed": 3,
         "total_lines_processed": 1500,
         "malformed_lines": 12,
         "time_range_used": "2024-01-15 00:00:00 to 2024-01-15 23:59:59"
       },
       "severity_counts": {"ERROR": 45, "WARNING": 120, "INFO": 300},
       "top_errors": [{"message": "Connection timeout", "count": 15}, ...],
       "component_breakdown": {"Database": 80, "API": 120, ...}
     }
     ```
   - **Error Log** (`/app/reports/errors.txt`): List of malformed lines with file and line number

## Expected Outputs

The tests will verify:
- `/app/reports/log_summary.csv` exists with correct CSV format and hourly data (0-23 hours)
- `/app/reports/analysis.json` exists with valid JSON structure matching the schema above
- `/app/reports/errors.txt` exists (even if empty)
- All calculations are accurate based on the input logs
- Time filtering is correctly applied (inclusive of start and end)
- Severity filtering respects the configuration