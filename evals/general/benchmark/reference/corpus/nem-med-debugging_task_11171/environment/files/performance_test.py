#!/usr/bin/env python3
"""Performance test comparing sync vs async implementations"""
import asyncio
import time
import json
import sys
from pipeline import main_processing_pipeline
import random

class SyncDataProcessor:
    """Synchronous version for baseline comparison"""
    
    def __init__(self, batch_size: int = 100):
        self.batch_size = batch_size
        self.results = []
        
    def process_record(self, record: dict) -> dict:
        """Process a single record synchronously"""
        processed = {}
        for key, value in record.items():
            if isinstance(value, (int, float)):
                processed[f"processed_{key}"] = value * 2 + random.random()
            else:
                processed[f"processed_{key}"] = str(value).upper()
        
        processed["timestamp"] = time.time()
        processed["processing_id"] = id(self)
        return processed
    
    def process_batch(self, records: list) -> list:
        """Process batch synchronously"""
        return [self.process_record(r) for r in records]
    
    def process_stream_sync(self, data):
        """Synchronous processing"""
        all_results = []
        position = 0
        
        while position < len(data):
            batch = data[position:position + self.batch_size]
            batch_results = self.process_batch(batch)
            all_results.extend(batch_results)
            position += self.batch_size
            
        return all_results


def run_sync_baseline(data_file: str):
    """Run synchronous baseline"""
    with open(data_file, 'r') as f:
        data = [json.loads(line) for line in f]
    
    processor = SyncDataProcessor()
    
    start = time.time()
    results = processor.process_stream_sync(data)
    elapsed = time.time() - start
    
    return {
        "mode": "sync_baseline",
        "time_seconds": elapsed,
        "records_processed": len(results),
        "throughput_rps": len(results) / elapsed if elapsed > 0 else 0
    }


async def run_async_current(data_file: str):
    """Run current async implementation"""
    start = time.time()
    result = await main_processing_pipeline(data_file)
    elapsed = time.time() - start
    
    return {
        "mode": "async_current",
        "time_seconds": elapsed,
        "records_processed": result.get("records_processed", 0),
        "throughput_rps": result.get("records_processed", 0) / elapsed if elapsed > 0 else 0
    }


def main():
    """Run performance comparison"""
    data_file = "/app/sample_data.jsonl"
    
    print("=" * 60)
    print("PERFORMANCE COMPARISON")
    print("=" * 60)
    
    # Run sync baseline
    print("\n1. Running synchronous baseline...")
    sync_result = run_sync_baseline(data_file)
    print(f"   Time: {sync_result['time_seconds']:.3f}s")
    print(f"   Throughput: {sync_result['throughput_rps']:.1f} records/sec")
    
    # Run async current
    print("\n2. Running current async implementation...")
    async_result = asyncio.run(run_async_current(data_file))
    print(f"   Time: {async_result['time_seconds']:.3f}s")
    print(f"   Throughput: {async_result['throughput_rps']:.1f} records/sec")
    
    # Calculate regression
    regression = async_result['time_seconds'] / sync_result['time_seconds']
    print(f"\n3. Performance regression: {regression:.1f}x slower")
    
    if regression > 2:
        print(f"   ⚠️  SIGNIFICANT REGRESSION DETECTED!")
        print(f"   Async is {regression:.1f}x slower than sync")
    else:
        print(f"   ✅ Performance acceptable")
    
    # Save results
    results = {
        "sync_baseline": sync_result,
        "async_current": async_result,
        "regression_factor": regression,
        "test_timestamp": time.time()
    }
    
    with open("/app/performance_results.json", "w") as f:
        json.dump(results, f, indent=2)
    
    print(f"\nResults saved to /app/performance_results.json")
    
    return results


if __name__ == "__main__":
    main()