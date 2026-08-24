## Build System Configuration Task: JSON to CSV Build Pipeline

You are tasked with creating a simple build system that processes JSON data and converts it to CSV format. This task tests basic software engineering skills in build configuration, file I/O operations, and data format conversion.

## Your Task

1. **Create a Makefile** at `/app/Makefile` with the following targets:
   - `convert`: Converts `/app/data/input.json` to `/app/output/results.csv`
   - `validate`: Runs validation checks on the output file
   - `clean`: Removes all generated files
   - `all`: Runs both `convert` and `validate` (default target)

2. **Implement the conversion script** at `/app/scripts/convert.py` that:
   - Reads the JSON file from `/app/data/input.json`
   - Converts it to CSV format with the following specifications:
     * First row must contain headers: `id,name,score,category`
     * Each subsequent row contains the corresponding data
     * All fields should be properly quoted (use double quotes)
     * Use comma as delimiter
   - Saves the output to `/app/output/results.csv`

3. **Implement the validation script** at `/app/scripts/validate.py` that:
   - Checks if `/app/output/results.csv` exists
   - Validates the CSV structure has exactly 4 columns
   - Ensures all required headers are present
   - Outputs validation status to `/app/output/validation_report.txt` with:
     * First line: "VALIDATION REPORT"
     * Second line: "Status: PASS" or "Status: FAIL"
     * Third line: "Timestamp: [current datetime in ISO format]"
     * Subsequent lines: Any error messages (if validation fails)

## Expected Outputs

- `/app/Makefile`: Makefile with the four required targets
- `/app/scripts/convert.py`: Python script that converts JSON to CSV
- `/app/scripts/validate.py`: Python script that validates CSV format
- `/app/output/results.csv`: Generated CSV file with data from input.json
- `/app/output/validation_report.txt`: Validation report with status

## Input Data

The input JSON file at `/app/data/input.json` contains student data in this format:
```json
[
  {"id": 1, "name": "Alice Johnson", "score": 85, "category": "A"},
  {"id": 2, "name": "Bob Smith", "score": 92, "category": "A"},
  {"id": 3, "name": "Charlie Brown", "score": 78, "category": "B"}
]
```

## Test Expectations

The tests will:
1. Verify all required files exist
2. Run `make all` and check that both conversion and validation complete successfully
3. Verify the CSV file has correct structure and content
4. Check the validation report contains "Status: PASS"
5. Ensure the clean target removes generated files

## Important Notes

- The Makefile should work with standard `make` (no GNU extensions required)
- Python scripts should handle errors gracefully (e.g., file not found)
- All paths in the Makefile should be absolute or relative to `/app`
- The validation script must exit with code 0 on success, non-zero on failure