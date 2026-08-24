# Debugging Task: Concurrent File Processing Performance Issue

## Problem Description

You are debugging a file processing system that has recently become extremely slow. The system processes multiple log files concurrently, but performance has degraded significantly after a recent update. The system should process 100 log files in under 10 seconds, but now takes over 2 minutes.

You've been provided with:
1. A buggy Python script at `/app/file_processor.py`
2. A directory `/app/logs/` containing 100 log files
3. A performance baseline at `/app/performance_baseline.json`

## Your Task

1. **Diagnose the Performance Issue**:
   - Run the provided script and measure its execution time
   - Use Python profiling tools to identify bottlenecks
   - Analyze the concurrency pattern for inefficiencies

2. **Fix the Issues**:
   - Correct the performance problems in `/app/file_processor.py`
   - Maintain thread safety and correct output
   - Ensure the script completes within the 10-second target

3. **Generate Debug Report**:
   - Create `/app/debug_report.json` with:
     - `original_execution_time`: float (seconds)
     - `fixed_execution_time`: float (seconds)
     - `bottlenecks_found`: array of strings describing each bottleneck
     - `fixes_applied`: array of strings describing each fix
     - `thread_safe`: boolean (true/false)
     - `output_matches_baseline`: boolean (true/false)
   - The report must be valid JSON and parseable by `json.load()`

4. **Validate Correctness**:
   - Verify that the fixed script produces the same output as the baseline
   - The output format is a dictionary mapping filename to processed data

## Expected Outputs

- `/app/file_processor.py`: Your fixed version of the script
- `/app/debug_report.json`: Debug report with the specified structure
- The script should execute successfully without errors when run with `python3 /app/file_processor.py`

## Success Criteria

1. **Performance**: Fixed script must process all files in ≤10 seconds
2. **Correctness**: Output must match the baseline exactly
3. **Thread Safety**: No race conditions or deadlocks
4. **Report**: Complete debug report with accurate measurements

## Constraints

- Do not change the algorithm's purpose (processing log files)
- Do not use external packages beyond Python standard library
- Maintain the same function signatures and public API
- Preserve all original functionality