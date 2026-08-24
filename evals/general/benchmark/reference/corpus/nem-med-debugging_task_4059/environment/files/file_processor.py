import os
import json
import threading
import time
from pathlib import Path
from collections import defaultdict
import re

class LogProcessor:
    def __init__(self):
        self.lock = threading.Lock()
        self.results = {}
        self.processed_count = 0
        self.start_time = None
        
    def process_file(self, filepath):
        """Process a single log file."""
        # Excessive lock duration - holds lock during entire I/O operation
        with self.lock:
            try:
                # Inefficient: Reading entire file at once for small processing
                with open(filepath, 'r') as f:
                    content = f.read()
                
                # Multiple passes over the same data
                lines = content.split('\n')
                
                # Inefficient nested loops
                error_count = 0
                warning_count = 0
                info_count = 0
                
                for line in lines:
                    if 'ERROR' in line:
                        error_count += 1
                    if 'WARNING' in line:
                        warning_count += 1
                    if 'INFO' in line:
                        info_count += 1
                
                # More inefficient string operations
                unique_words = set()
                for line in lines:
                    words = line.split()
                    for word in words:
                        unique_words.add(word)
                
                # Store results - more lock contention
                filename = os.path.basename(filepath)
                self.results[filename] = {
                    'error_count': error_count,
                    'warning_count': warning_count,
                    'info_count': info_count,
                    'unique_words': len(unique_words),
                    'line_count': len(lines)
                }
                
                # Global counter update - more lock contention
                self.processed_count += 1
                
                # Simulate some CPU work (inefficiently)
                for i in range(1000):
                    _ = i * i
                    
            except Exception as e:
                print(f"Error processing {filepath}: {e}")
    
    def process_all_concurrently(self, log_dir):
        """Process all log files concurrently (buggy implementation)."""
        self.start_time = time.time()
        threads = []
        
        log_files = list(Path(log_dir).glob('*.log'))
        
        # Creating too many threads
        for log_file in log_files:
            thread = threading.Thread(target=self.process_file, args=(str(log_file),))
            threads.append(thread)
            thread.start()
        
        # Inefficient thread management
        for thread in threads:
            thread.join()
        
        self.end_time = time.time()
        return self.results
    
    def get_performance_stats(self):
        """Get performance statistics."""
        if self.start_time and self.end_time:
            return {
                'execution_time': self.end_time - self.start_time,
                'files_processed': self.processed_count
            }
        return {}

def process_all_logs(log_dir):
    """Main function to process all logs."""
    processor = LogProcessor()
    results = processor.process_all_concurrently(log_dir)
    
    # Sort results for consistent output
    sorted_results = dict(sorted(results.items()))
    
    # Add performance stats
    stats = processor.get_performance_stats()
    sorted_results['_performance'] = stats
    
    return sorted_results

if __name__ == "__main__":
    # Entry point for testing
    log_dir = "/app/logs"
    
    if os.path.exists(log_dir):
        results = process_all_logs(log_dir)
        
        # Remove performance stats from main output
        if '_performance' in results:
            perf_stats = results.pop('_performance')
            print(f"Processed {perf_stats.get('files_processed', 0)} files in {perf_stats.get('execution_time', 0):.2f} seconds")
        
        # Print summary
        print(f"Processed {len(results)} log files")
        
        # Save results to file (for verification)
        with open('/app/output.json', 'w') as f:
            json.dump(results, f, indent=2)
    else:
        print(f"Log directory not found: {log_dir}")