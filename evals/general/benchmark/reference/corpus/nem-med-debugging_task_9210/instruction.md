# Concurrent File Processor Race Condition

## Your Task

You've inherited a Python script that processes multiple files concurrently but has performance issues and occasional data corruption. The script reads CSV files, processes them, and writes results to a database, but under heavy load it produces incorrect results and sometimes crashes.

Your debugging task has three parts:

1. **Diagnose the root cause** - Identify the concurrency bug(s) causing data corruption
2. **Fix the performance bottleneck** - Profile the code and optimize the slowest operation
3. **Implement a working solution** - Fix the bugs while maintaining concurrency benefits

## Provided Files

The workspace contains:

- `/app/processor.py` - Main script with the buggy implementation
- `/app/data/` - Directory with 100 sample CSV files to process
- `/app/test_results.log` - Log file from a test run showing failures
- `/app/requirements.txt` - Dependencies (already installed)

## Bug Manifestation

When you run the processor, you'll see:
- Random "KeyError" or "NoneType" exceptions in worker threads
- Final summary counts don't match expected totals
- Some output records are duplicated, others are missing
- Performance degrades with more worker threads

## Investigation Steps

1. **Analyze the logs**: Examine `/app/test_results.log` to understand failure patterns
2. **Run the processor**: Execute `python3 processor.py --workers=4 --verbose` to reproduce issues
3. **Profile performance**: Use Python's cProfile or time measurements to identify bottlenecks
4. **Trace data flow**: Add debug logging to understand how data moves between threads
5. **Identify race conditions**: Look for shared state accessed without proper synchronization

## Expected Fixes

Your solution must:

1. **Fix concurrency bugs**: Prevent race conditions and ensure thread-safe operations
2. **Optimize performance**: Reduce processing time by at least 30% compared to current implementation
3. **Maintain correctness**: Ensure all 100 files are processed exactly once with accurate counts
4. **Preserve concurrency**: Keep the multi-threaded architecture (don't switch to single-threaded)

## Output Requirements

Create the following output files:

1. `/app/fixed_processor.py` - Your corrected implementation
2. `/app/debug_report.md` - Analysis report containing:
   - Root cause diagnosis (what was broken and why)
   - Performance bottleneck identified
   - Changes made to fix the issues
   - Before/after performance comparison
3. `/app/validation_results.json` - JSON file with validation results:
   ```json
   {
     "total_records": 123456,
     "unique_records": 123456,
     "processing_time_seconds": 12.34,
     "errors_found": 0,
     "performance_improvement": 0.35
   }
   ```

## Verification Criteria

The tests will verify:

1. All CSV files are processed completely
2. No data corruption (counts match expected values)
3. Thread-safe execution (no race conditions)
4. Performance improvement meets target
5. All output files are correctly formatted

## Hints

- Look for improper use of global variables across threads
- Check file I/O patterns that might cause contention
- Examine how worker results are aggregated
- Watch for mutable data structures shared between threads without synchronization

**Success Condition**: Your fixed processor must complete without errors and produce correct totals within the performance target.