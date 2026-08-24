import csv
import threading
import time
from pathlib import Path
from collections import defaultdict
import random

class FileProcessor:
    def __init__(self, num_workers=4):
        self.num_workers = num_workers
        self.results = {}
        self.processed_count = 0
        self.error_count = 0
        self.lock = threading.Lock()
        self.global_data = defaultdict(int)
        
    def process_file(self, file_path):
        """Process a single CSV file and extract data."""
        try:
            # Simulate variable processing time
            time.sleep(random.uniform(0.01, 0.1))
            
            with open(file_path, 'r') as f:
                reader = csv.reader(f)
                rows = list(reader)
                
            # Skip header if present
            if rows and 'category' in rows[0][0].lower():
                rows = rows[1:]
            
            file_results = {}
            for row in rows:
                if len(row) >= 2:
                    category = row[0].strip()
                    try:
                        value = float(row[1])
                        # BUG: Race condition - accessing shared dict without proper sync
                        self.global_data[category] += value
                        file_results[category] = file_results.get(category, 0) + value
                    except ValueError:
                        self.error_count += 1
            
            # BUG: Race condition - updating shared results without atomic operation
            self.results[file_path.name] = file_results
            self.processed_count += 1
            
        except Exception as e:
            print(f"Error processing {file_path}: {e}")
            self.error_count += 1
    
    def worker_thread(self, file_queue):
        """Worker thread function - processes files from queue."""
        while True:
            try:
                file_path = file_queue.pop()
            except IndexError:
                break
            
            self.process_file(file_path)
    
    def process_files(self, data_dir):
        """Process all CSV files in directory."""
        data_path = Path(data_dir)
        csv_files = list(data_path.glob('*.csv'))
        
        # Shuffle to increase chance of race conditions
        random.shuffle(csv_files)
        
        # Create file queue
        file_queue = list(csv_files)
        
        # Start worker threads
        threads = []
        for i in range(self.num_workers):
            # BUG: All threads share the same queue object
            thread = threading.Thread(target=self.worker_thread, args=(file_queue,))
            thread.start()
            threads.append(thread)
        
        # Wait for completion
        for thread in threads:
            thread.join()
        
        return self.aggregate_results()
    
    def aggregate_results(self):
        """Aggregate results from all files."""
        # BUG: Inefficient aggregation - recalculates everything
        final_results = defaultdict(float)
        all_categories = set()
        
        # Collect all categories first (inefficient)
        for file_result in self.results.values():
            all_categories.update(file_result.keys())
        
        # Sum values for each category (O(n*m) where n=files, m=categories)
        for category in all_categories:
            total = 0.0
            for file_result in self.results.values():
                total += file_result.get(category, 0)
            final_results[category] = total
        
        return {
            'total_files': self.processed_count,
            'total_records': sum(len(r) for r in self.results.values()),
            'results': dict(final_results),
            'errors': self.error_count
        }

def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='Process CSV files concurrently')
    parser.add_argument('--workers', type=int, default=4, help='Number of worker threads')
    parser.add_argument('--verbose', action='store_true', help='Enable verbose output')
    parser.add_argument('--test-mode', action='store_true', help='Run in test mode with reduced dataset')
    args = parser.parse_args()
    
    data_dir = '/app/data'
    
    if args.test_mode:
        # Use only first 10 files for testing
        data_dir = '/app/data/test'
    
    processor = FileProcessor(num_workers=args.workers)
    
    print(f"Starting processing with {args.workers} workers...")
    start_time = time.time()
    
    results = processor.process_files(data_dir)
    
    elapsed = time.time() - start_time
    
    print(f"\nProcessing completed in {elapsed:.2f} seconds")
    print(f"Files processed: {results['total_files']}")
    print(f"Total records: {results['total_records']}")
    print(f"Errors: {results['errors']}")
    
    if args.verbose:
        print("\nResults by category:")
        for category, total in results['results'].items():
            print(f"  {category}: {total:.2f}")
    
    return results

if __name__ == '__main__':
    main()