# Log Analysis and Archive Management System

You are tasked with building a log analysis and archive management system. Your program will process log files from multiple sources, extract key information, and create an organized archive with analysis results.

## Your Task

You have been provided with a directory `/app/logs/` containing mixed log files from various systems. These logs have different formats and some may be corrupted. Your program must:

### 1. Directory Traversal and File Analysis
- Recursively traverse the `/app/logs/` directory to find all files with `.log` or `.txt` extensions
- For each file found, analyze its contents and extract the following metadata:
  - File path (relative to `/app/logs/`)
  - File size in bytes
  - Number of lines
  - Number of error lines (lines containing "ERROR" or "error")
  - Number of warning lines (lines containing "WARN" or "warning")
  - Timestamp of the last log entry (extract the last timestamp found in the file)
- Handle any encoding issues gracefully (some files might be UTF-8, others ASCII)
- Skip files that are completely unreadable (record them separately)

### 2. Data Aggregation and Analysis
- Create a summary of all analyzed files:
  - Total number of files processed
  - Total number of error lines across all files
  - Total number of warning lines across all files
  - Average file size
  - Most recent timestamp found across all files
- Identify the top 3 files with the highest error counts

### 3. Archive Creation and Organization
- Create a new directory structure at `/app/archive/` with the following organization:
  ```
  /app/archive/
  ├── processed_logs/
  │   ├── high_priority/    (files with >10 errors)
  │   ├── medium_priority/  (files with 1-10 errors)
  │   └── low_priority/     (files with 0 errors)
  ├── summary/
  │   └── analysis.json
  └── failed_files.txt
  ```
- Copy (do not move) each processed log file to the appropriate priority directory based on its error count
- Preserve the original directory structure within each priority folder
- For files that failed to process, record their paths in `/app/archive/failed_files.txt`

### 4. Output Generation
Create `/app/archive/summary/analysis.json` with the following structure:
```json
{
  "analysis_timestamp": "ISO-8601 timestamp of when analysis was run",
  "summary": {
    "total_files_processed": 123,
    "total_error_count": 456,
    "total_warning_count": 789,
    "average_file_size_bytes": 12345.6,
    "most_recent_log_timestamp": "YYYY-MM-DD HH:MM:SS",
    "processing_duration_seconds": 12.34
  },
  "top_error_files": [
    {
      "file_path": "relative/path/to/file.log",
      "error_count": 50,
      "warning_count": 10,
      "file_size_bytes": 12345
    },
    ...
  ],
  "file_statistics": [
    {
      "file_path": "relative/path/to/file.log",
      "size_bytes": 12345,
      "line_count": 500,
      "error_count": 5,
      "warning_count": 12,
      "last_timestamp": "YYYY-MM-DD HH:MM:SS"
    },
    ...
  ]
}
```

## Log File Format Notes
- Timestamps in logs may appear in various formats:
  - `YYYY-MM-DD HH:MM:SS`
  - `MM/DD/YYYY HH:MM:SS`
  - `DD-MMM-YYYY HH:MM:SS` (e.g., 01-Jan-2024 14:30:00)
- Error detection should be case-insensitive
- Some files may contain binary data or be corrupted - handle these gracefully

## Expected Outputs
- `/app/archive/` directory with complete structure as described above
- `/app/archive/summary/analysis.json` with analysis results
- `/app/archive/failed_files.txt` listing unprocessable files (if any)
- Log files copied to appropriate priority directories with preserved structure

## Testing Criteria
Tests will verify:
1. The archive directory structure exists with all required subdirectories
2. `analysis.json` is valid JSON with all required fields
3. File counts and error totals match the input data
4. Log files are correctly categorized by error count
5. Failed files are properly recorded
6. Directory structure is preserved in the archive