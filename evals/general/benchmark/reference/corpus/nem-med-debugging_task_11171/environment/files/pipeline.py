import asyncio
import json
import time
from collections import defaultdict
from typing import List, Dict, Any
import random

class DataProcessor:
    """Process streaming sensor data asynchronously"""
    
    def __init__(self, batch_size: int = 100):
        self.batch_size = batch_size
        self.results = []
        self.lock = asyncio.Lock()
        self.processing_times = []
        
    async def process_record(self, record: Dict[str, Any]) -> Dict[str, Any]:
        """Process a single record"""
        # Simulate CPU-intensive processing
        await asyncio.sleep(0)  # Yield control
        
        # INEFFICIENT: Creates new dict for each transformation
        processed = {}
        for key, value in record.items():
            if isinstance(value, (int, float)):
                # Heavy computation simulated
                processed[f"processed_{key}"] = value * 2 + random.random()
            else:
                processed[f"processed_{key}"] = str(value).upper()
        
        # Add metadata
        processed["timestamp"] = time.time()
        processed["processing_id"] = id(self)
        
        return processed
    
    async def process_batch_sync_style(self, records: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Process batch - BUT WITH SYNC STYLE IN ASYNC CONTEXT"""
        # CRITICAL BUG: This processes sequentially despite being async
        batch_results = []
        for record in records:
            result = await self.process_record(record)
            batch_results.append(result)
            
            # INEFFICIENT: Frequent locking for statistics
            async with self.lock:
                self.processing_times.append(time.time())
                
        return batch_results
    
    async def aggregate_results(self, results: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Aggregate processed results"""
        # MEMORY LEAK: Creates unnecessary intermediate structures
        aggregated = defaultdict(list)
        
        for result in results:
            for key, value in result.items():
                if isinstance(value, (int, float)):
                    aggregated[key].append(value)
        
        # Calculate statistics - INEFFICIENT multiple passes
        stats = {}
        for key, values in aggregated.items():
            if values:
                stats[f"{key}_mean"] = sum(values) / len(values)
                stats[f"{key}_min"] = min(values)
                stats[f"{key}_max"] = max(values)
                stats[f"{key}_count"] = len(values)
                
                # UNNECESSARY: Sorted copy just for median
                sorted_values = sorted(values)
                mid = len(sorted_values) // 2
                if len(sorted_values) % 2 == 0:
                    stats[f"{key}_median"] = (sorted_values[mid-1] + sorted_values[mid]) / 2
                else:
                    stats[f"{key}_median"] = sorted_values[mid]
        
        return dict(stats)
    
    async def process_stream(self, data_stream) -> Dict[str, Any]:
        """Main processing pipeline"""
        all_results = []
        
        # PROCESSING BOTTLENECK: Processes all batches sequentially
        batch_count = 0
        while True:
            batch = await data_stream.read_batch(self.batch_size)
            if not batch:
                break
                
            # CRITICAL: Each batch waits for previous to complete
            batch_results = await self.process_batch_sync_style(batch)
            all_results.extend(batch_results)
            
            # UNNECESSARY BLOCKING: Aggregates after each batch
            if batch_count % 10 == 0:
                _ = await self.aggregate_results(all_results)
                
            batch_count += 1
        
        # Final aggregation
        final_stats = await self.aggregate_results(all_results)
        return final_stats


class DataStream:
    """Simulates a data stream"""
    
    def __init__(self, data_file: str):
        self.data_file = data_file
        self.position = 0
        self.data = []
        self._load_data()
        
    def _load_data(self):
        """Load all data into memory - INEFFICIENT for large datasets"""
        with open(self.data_file, 'r') as f:
            for line in f:
                self.data.append(json.loads(line))
    
    async def read_batch(self, batch_size: int) -> List[Dict[str, Any]]:
        """Read batch with artificial delay"""
        # ARTIFICIAL DELAY: Simulates network latency
        await asyncio.sleep(0.001)
        
        start = self.position
        end = min(start + batch_size, len(self.data))
        
        if start >= len(self.data):
            return []
        
        batch = self.data[start:end]
        self.position = end
        
        return batch


async def main_processing_pipeline(input_file: str, batch_size: int = 100):
    """Main entry point"""
    processor = DataProcessor(batch_size)
    stream = DataStream(input_file)
    
    # TIMING ISSUE: No proper context manager for timing
    start_time = time.time()
    
    try:
        results = await processor.process_stream(stream)
        
        # RESOURCE LEAK: Never cleaned up
        processing_time = time.time() - start_time
        
        return {
            "results": results,
            "processing_time": processing_time,
            "records_processed": len(processor.results),
            "avg_batch_time": sum(processor.processing_times) / len(processor.processing_times) if processor.processing_times else 0
        }
        
    except Exception as e:
        print(f"Processing failed: {e}")
        raise


if __name__ == "__main__":
    # Quick test
    import sys
    result = asyncio.run(main_processing_pipeline(sys.argv[1] if len(sys.argv) > 1 else "/app/sample_data.jsonl"))
    print(f"Processed in {result['processing_time']:.2f}s")