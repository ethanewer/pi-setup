# Performance Degradation Debugging Task

You are debugging a performance regression in a data processing pipeline. A recent code change has caused a 10x slowdown in processing large datasets.

## Background

The pipeline processes streaming sensor data with the following requirements:
1. Process up to 1000 concurrent data streams
2. Maintain real-time processing (<100ms latency per batch)
3. Handle data bursts without memory exhaustion

The pipeline recently transitioned from synchronous processing to asynchronous using `asyncio`. The migration was supposed to improve performance but instead caused severe degradation.

## Your Task

1. **Diagnose the performance bottleneck** by analyzing the provided codebase
2. **Identify the root cause** of the 10x slowdown
3. **Fix the implementation** while preserving all functionality
4. **Verify the fix** meets performance requirements

### Provided Files

- `/app/pipeline.py` - Main processing pipeline with performance issues
- `/app/performance_test.py` - Test script that demonstrates the slowdown
- `/app/sample_data.jsonl` - Sample input data (1000 records)
- `/app/requirements.txt` - Python dependencies

### Investigation Steps

1. **Run the performance test** to confirm the regression:
   ```bash
   python3 /app/performance_test.py
   ```
   This will output baseline (sync) vs current (async) performance metrics.

2. **Analyze the pipeline code** to identify:
   - Inefficient concurrency patterns
   - Resource contention issues
   - Memory management problems
   - Blocking operations in async context

3. **Use profiling tools** to pinpoint bottlenecks:
   - `cProfile` for CPU bottlenecks
   - Memory profiler for allocation patterns
   - `asyncio` debugging utilities

4. **Implement fixes** that address the root cause while:
   - Maintaining the async architecture
   - Preserving data processing correctness
   - Avoiding memory leaks
   - Ensuring thread safety

5. **Validate the fix** by:
   - Running the performance test again
   - Verifying all tests pass
   - Checking memory usage doesn't grow unbounded

## Expected Outputs

1. **Fixed pipeline code** - Save your corrected version to `/app/fixed_pipeline.py`

2. **Debugging report** - Save analysis to `/app/debug_report.json` with:
   ```json
   {
     "root_cause": "string describing the main issue",
     "identified_bottlenecks": ["list", "of", "specific", "problems"],
     "applied_fixes": ["list", "of", "changes", "made"],
     "performance_improvement": {
       "before_ms": float,
       "after_ms": float,
       "improvement_factor": float
     },
     "memory_usage": {
       "before_mb": float,
       "after_mb": float,
       "peak_reduction_percent": float
     }
   }
   ```

3. **Validation output** - Run the final test and save results to `/app/validation.txt`:
   ```
   Test Results:
   - Processing time: X ms
   - Memory peak: Y MB
   - Records processed: Z
   - All tests passed: true/false
   ```

## Success Criteria

Your solution must achieve:
- At least 5x performance improvement over the broken async version
- Memory usage stable (no unbounded growth)
- All 1000 records processed correctly
- No data corruption or loss
- Thread-safe execution