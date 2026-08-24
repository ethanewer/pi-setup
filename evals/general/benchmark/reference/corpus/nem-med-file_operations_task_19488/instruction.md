## CSV Data Reconciliation and Archive System

You are tasked with building a file processing system that reconciles data from multiple CSV files and creates a compressed archive of the results. This task requires careful file I/O operations, data validation, and archive management.

## Your Task

You have been given three input CSV files at the following locations:
1. `/app/data/source_a.csv` - Contains primary transaction data
2. `/app/data/source_b.csv` - Contains secondary transaction data  
3. `/app/data/reference.csv` - Contains validation rules and metadata

**Step 1: Data Validation and Cleaning**
- Read all three CSV files using proper error handling (skip malformed rows, log errors)
- Validate each row in source files against these rules:
  - Transaction IDs must be 8-character alphanumeric strings
  - Amounts must be positive numbers with exactly 2 decimal places
  - Dates must be in YYYY-MM-DD format
- Create a validation report at `/app/output/validation_report.txt` containing:
  - Total rows processed from each file
  - Number of valid rows kept
  - Number of invalid rows skipped (with examples)
  - Any parsing errors encountered

**Step 2: Data Reconciliation**
- The two source files contain overlapping transaction data. For transactions that appear in BOTH files:
  - Compare the amounts - if they differ by more than 0.01, flag as "MISMATCH"
  - If amounts match within tolerance (≤0.01), mark as "VERIFIED"
  - If transaction appears in only one file, mark as "UNIQUE_[SOURCE]"
- Use the reference file to categorize transactions by type
- Output reconciled results to `/app/output/reconciled_data.json` with this structure:
```json
{
  "statistics": {
    "total_transactions": 1234,
    "verified": 567,
    "mismatches": 89,
    "unique_source_a": 345,
    "unique_source_b": 233
  },
  "transactions": [
    {
      "id": "ABC12345",
      "type": "REFERENCE_TYPE",
      "status": "VERIFIED",
      "amount_a": 100.50,
      "amount_b": 100.50,
      "date": "2024-01-15"
    }
  ]
}
```

**Step 3: Archive Creation**
- Create a directory `/app/output/backup/` with current timestamp as subdirectory (format: YYYYMMDD_HHMMSS)
- Copy all original input files to this backup directory
- Create a ZIP archive at `/app/output/archive.zip` containing:
  1. The backup directory with input files
  2. The validation report
  3. The reconciled data JSON file
- The ZIP should maintain directory structure and be compressed
- After creating the archive, delete the backup directory (keep only the ZIP)

**Step 4: Summary Report**
- Generate a final summary at `/app/output/summary.txt` with:
  - Timestamp of processing start and end
  - Total processing time in seconds
  - Archive size in bytes
  - MD5 checksum of the archive file (use hashlib or external command)
  - List of files contained in the archive

## Expected Outputs
- `/app/output/validation_report.txt` - Text file with validation statistics
- `/app/output/reconciled_data.json` - JSON file with reconciled transaction data
- `/app/output/archive.zip` - ZIP archive containing all results and inputs
- `/app/output/summary.txt` - Final summary with metrics and checksum

## Success Criteria
1. All four output files must be created with correct formats
2. The ZIP archive must contain exactly 5 files (3 input + 2 output)
3. JSON output must be valid and parsable with `json.load()`
4. Validation report must clearly show what data was kept/skipped
5. Archive must be properly compressed and extractable
6. No temporary files or backup directory should remain after processing

## Notes
- Handle large files efficiently (stream processing recommended)
- Use appropriate error handling for missing files, permission issues
- Ensure the system is idempotent (can be run multiple times)
- Log any errors to stderr but continue processing when possible