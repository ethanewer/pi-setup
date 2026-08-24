import os
import json
import asyncio
import time
import pytest
import sys
from unittest.mock import Mock, patch

def test_fixed_pipeline_exists():
    """Verify fixed pipeline file was created."""
    assert os.path.exists('/app/fixed_pipeline.py'), "Fixed pipeline file not found"

def test_debug_report_exists():
    """Verify debug report file was created."""
    assert os.path.exists('/app/debug_report.json'), "Debug report file not found"

def test_debug_report_format():
    """Verify debug report has correct structure."""
    with open('/app/debug_report.json', 'r') as f:
        report = json.load(f)
    
    # Check required fields
    required_fields = ['root_cause', 'identified_bottlenecks', 'applied_fixes', 
                      'performance_improvement', 'memory_usage']
    for field in required_fields:
        assert field in report, f"Missing field in report: {field}"
    
    # Check performance improvement structure
    perf = report['performance_improvement']
    assert 'before_ms' in perf
    assert 'after_ms' in perf
    assert 'improvement_factor' in perf
    
    # Verify improvement factor is reasonable
    assert perf['improvement_factor'] >= 5.0, f"Performance improvement insufficient: {perf['improvement_factor']}x (need 5x+)"

def test_validation_output_exists():
    """Verify validation output was created."""
    assert os.path.exists('/app/validation.txt'), "Validation output file not found"

def test_fixed_pipeline_performance():
    """Test that fixed pipeline meets performance requirements."""
    # Import the fixed pipeline
    sys.path.insert(0, '/app')
    try:
        import fixed_pipeline as fp
    except ImportError:
        pytest.fail("Could not import fixed_pipeline module")
    
    # Run performance test
    test_data = []
    for i in range(1000):
        test_data.append({
            "sensor_id": f"sensor_{i}",
            "value": i % 100,
            "timestamp": time.time() + i,
            "location": f"loc_{i % 10}",
            "status": "active" if i % 20 != 0 else "warning"
        })
    
    # Create a mock data stream
    class MockStream:
        def __init__(self, data):
            self.data = data
            self.pos = 0
        
        async def read_batch(self, batch_size):
            if self.pos >= len(self.data):
                return []
            batch = self.data[self.pos:self.pos + batch_size]
            self.pos += batch_size
            await asyncio.sleep(0)  # Yield control
            return batch
    
    # Test processing time
    start_time = time.time()
    
    async def run_test():
        processor = fp.DataProcessor(batch_size=100)
        stream = MockStream(test_data)
        
        # Monkey-patch the stream into processor
        results = await processor.process_stream(stream)
        return results
    
    result = asyncio.run(run_test())
    elapsed = time.time() - start_time
    
    # Performance requirement: < 2 seconds for 1000 records
    assert elapsed < 2.0, f"Processing too slow: {elapsed:.2f}s for 1000 records"
    
    # Verify all records processed
    assert 'records_processed' in result or 'processing_time' in result

def test_memory_stability():
    """Test that memory usage doesn't grow unbounded."""
    import psutil
    import subprocess
    
    # Run the fixed pipeline in a subprocess and monitor memory
    process = subprocess.Popen(
        [sys.executable, '-c', """
import asyncio
import sys
sys.path.insert(0, '/app')
import fixed_pipeline as fp
import json

async def test():
    # Create test data
    data = []
    for i in range(2000):
        data.append({
            "sensor_id": f"test_{i}",
            "value": i % 50,
            "timestamp": 1625097600 + i,
            "location": "test",
            "status": "active"
        })
    
    class TestStream:
        def __init__(self, data):
            self.data = data
            self.pos = 0
        
        async def read_batch(self, size):
            if self.pos >= len(self.data):
                return []
            batch = self.data[self.pos:self.pos + size]
            self.pos += size
            await asyncio.sleep(0)
            return batch
    
    processor = fp.DataProcessor(batch_size=50)
    stream = TestStream(data)
    return await processor.process_stream(stream)

result = asyncio.run(test())
print("Test completed")
"""],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    
    # Get memory info
    p = psutil.Process(process.pid)
    
    memory_samples = []
    try:
        for _ in range(10):  # Sample memory 10 times
            memory_samples.append(p.memory_info().rss / 1024 / 1024)  # MB
            time.sleep(0.1)
        
        process.wait(timeout=5)
    except (psutil.NoSuchProcess, subprocess.TimeoutExpired):
        pass
    
    # Check memory didn't grow excessively
    if len(memory_samples) > 3:
        # Check that memory doesn't continuously grow
        # Allow some variation but not unbounded growth
        max_memory = max(memory_samples)
        min_memory = min(memory_samples)
        
        # Memory shouldn't grow more than 50MB during processing
        assert max_memory - min_memory < 50, f"Memory growth too high: {max_memory - min_memory:.1f}MB"

def test_concurrent_processing():
    """Test that pipeline can handle concurrent processing."""
    sys.path.insert(0, '/app')
    import fixed_pipeline as fp
    
    async def concurrent_test():
        # Create multiple processors
        processors = [fp.DataProcessor(batch_size=50) for _ in range(5)]
        
        # Create test data
        test_data = []
        for i in range(500):
            test_data.append({
                "id": i,
                "value": i * 1.5,
                "label": f"item_{i}"
            })
        
        class SharedStream:
            def __init__(self, data):
                self.data = data
                self.lock = asyncio.Lock()
                self.counters = [0] * len(processors)
            
            async def read_batch(self, batch_size, processor_idx):
                async with self.lock:
                    start = self.counters[processor_idx]
                    end = min(start + batch_size, len(self.data))
                    if start >= end:
                        return []
                    
                    batch = self.data[start:end]
                    self.counters[processor_idx] = end
                    await asyncio.sleep(0)
                    return batch
        
        stream = SharedStream(test_data)
        
        # Process concurrently
        tasks = []
        for idx, processor in enumerate(processors):
            # Create task for each processor
            task = asyncio.create_task(processor.process_stream(
                type('Stream', (), {
                    'read_batch': lambda self, size: stream.read_batch(size, idx)
                })()
            ))
            tasks.append(task)
        
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Verify no exceptions
        for result in results:
            if isinstance(result, Exception):
                pytest.fail(f"Concurrent processing failed: {result}")
        
        return True
    
    # Run concurrent test
    success = asyncio.run(concurrent_test())
    assert success, "Concurrent processing test failed"

def test_data_correctness():
    """Test that data is processed correctly without corruption."""
    sys.path.insert(0, '/app')
    import fixed_pipeline as fp
    import json
    
    # Load sample data
    with open('/app/sample_data.jsonl', 'r') as f:
        sample_data = [json.loads(line) for line in f]
    
    async def correctness_test():
        processor = fp.DataProcessor(batch_size=3)
        
        class TestStream:
            def __init__(self, data):
                self.data = data
                self.pos = 0
            
            async def read_batch(self, size):
                if self.pos >= len(self.data):
                    return []
                batch = self.data[self.pos:self.pos + size]
                self.pos += size
                await asyncio.sleep(0)
                return batch
        
        stream = TestStream(sample_data)
        result = await processor.process_stream(stream)
        
        # Check that result contains expected keys
        assert isinstance(result, dict), "Result should be a dictionary"
        
        # Check for processing statistics
        stats_keys = [k for k in result.keys() if k.endswith(('_mean', '_min', '_max', '_count', '_median'))]
        assert len(stats_keys) > 0, "Should have calculated statistics"
        
        return True
    
    success = asyncio.run(correctness_test())
    assert success, "Data correctness test failed"