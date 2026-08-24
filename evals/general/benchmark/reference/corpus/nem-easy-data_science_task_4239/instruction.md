# Customer Service Data Analyzer

You are a data scientist tasked with analyzing customer service call data. Your goal is to process the raw data file, compute key performance metrics, and generate a summary report.

## Your Task

1. **Load and inspect the data**: Read the customer service data from `/app/customer_calls.csv`. Examine the structure and data types of the dataset.

2. **Clean the data**: 
   - Remove any rows with missing values in critical columns (`call_id`, `duration_minutes`, `customer_rating`)
   - Convert `call_date` to datetime format
   - Ensure numeric columns (`duration_minutes`, `customer_rating`) have appropriate data types

3. **Compute summary statistics**:
   - Calculate the total number of calls
   - Calculate the average call duration (in minutes)
   - Calculate the average customer satisfaction rating (scale 1-5)
   - Count calls by `issue_type` category
   - Find the busiest day (date with most calls)

4. **Generate insights report**: Create a JSON report with the following structure:
   - `total_calls`: integer
   - `average_duration`: float (rounded to 2 decimal places)
   - `average_rating`: float (rounded to 2 decimal places)
   - `calls_by_issue`: object with issue types as keys and counts as values
   - `busiest_day`: string in "YYYY-MM-DD" format
   - `data_quality`: object with `rows_processed` (total rows after cleaning) and `rows_removed` (rows with missing values)

5. **Save results**: Save the cleaned dataset as `/app/cleaned_calls.csv` and the summary report as `/app/summary_report.json`.

## Expected Outputs

- `/app/cleaned_calls.csv`: CSV file with cleaned data (same columns as input, no missing values)
- `/app/summary_report.json`: JSON file with the exact structure described above

## Verification Criteria (What the tests will check)

1. **File existence**: Both output files must exist at the specified paths
2. **Data quality**: Cleaned CSV must have no missing values in critical columns
3. **Statistical accuracy**: Summary statistics must match expected values within tolerance
4. **Format compliance**: JSON report must have exactly the required keys and proper data types
5. **Date formatting**: Dates must be correctly parsed and formatted

## Sample Data Structure

The input CSV has the following columns:
- `call_id`: Unique identifier (string)
- `call_date`: Date of call (string, "YYYY-MM-DD")
- `duration_minutes`: Call length in minutes (float)
- `customer_rating`: Satisfaction score 1-5 (integer)
- `issue_type`: Category of issue (string: "billing", "technical", "account", "product")
- `agent_id`: Agent identifier (string)

## Example Output Format

```json
{
  "total_calls": 150,
  "average_duration": 8.75,
  "average_rating": 3.92,
  "calls_by_issue": {
    "billing": 45,
    "technical": 60,
    "account": 25,
    "product": 20
  },
  "busiest_day": "2024-03-15",
  "data_quality": {
    "rows_processed": 150,
    "rows_removed": 5
  }
}
```

**Note**: Use only standard Python data science libraries (pandas, numpy). The tests will verify your outputs match the expected format and values.