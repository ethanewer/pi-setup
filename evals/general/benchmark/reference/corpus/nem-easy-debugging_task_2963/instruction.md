## Python CSV Validator Debugging Task

You are given a Python script that validates CSV files against a configuration schema. The script is failing with an error when processing the provided input files. Your task is to debug and fix the issue.

## Your Task

1. **Run the validation script** located at `/app/main.py`
2. **Analyze the error message** to understand what's causing the failure
3. **Fix the bug** in either the code or configuration files
4. **Ensure the script runs successfully** and produces the expected output
5. **Save the validation results** to `/app/output/validation_report.json`

## File Structure

- `/app/main.py` - Main validation script
- `/app/config/schema.json` - Validation schema configuration
- `/app/data/input.csv` - Input data to validate
- `/app/output/` - Directory for output (initially empty)

## Expected Output

After fixing the bug, running the script should create:
- `/app/output/validation_report.json` - JSON file containing validation results

The output JSON must have this exact structure:
```json
{
  "total_records": 100,
  "valid_records": 95,
  "invalid_records": 5,
  "errors": [
    {
      "line_number": 12,
      "field": "age",
      "error": "Value must be positive integer"
    },
    {
      "line_number": 45,
      "field": "email",
      "error": "Invalid email format"
    }
  ]
}
```

## Specific Requirements

1. The script must run without any exceptions or errors
2. The output file must be valid JSON that can be parsed with `json.load()`
3. The "total_records" must match the number of rows in `/app/data/input.csv` (excluding header)
4. The sum of "valid_records" and "invalid_records" must equal "total_records"
5. Each error in the "errors" array must have "line_number", "field", and "error" keys

## Debugging Hints

- Start by running the script to see the error message
- Check the traceback carefully - it points to the exact line causing the issue
- The bug is a simple logic error that causes incorrect type checking
- The fix should be minimal (1-2 lines of code)

## Verification

The tests will:
1. Check that `/app/output/validation_report.json` exists
2. Validate the JSON structure and content matches the requirements
3. Verify that the statistics in the report are mathematically consistent