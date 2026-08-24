# Sales Data Quality Check and Summary Report

You are a data analyst at an e-commerce company. Your manager has asked you to perform a basic quality check on a sales dataset and generate a summary report.

## Your Task

1. **Load the data**: Read the sales data from `/app/sales_data.csv`. This file contains sales transactions with some quality issues.

2. **Data quality checks**: Perform the following quality checks:
   - Identify and count any rows with missing values (NaN) in any column
   - Identify and count any duplicate rows (exact matches across all columns)
   - Convert the `sale_date` column to proper datetime format (format: YYYY-MM-DD)

3. **Data cleaning**: 
   - Remove any duplicate rows (keep the first occurrence)
   - For rows with missing `customer_id`, fill with "UNKNOWN"
   - For rows with missing `amount`, fill with the column mean (rounded to 2 decimal places)

4. **Summary statistics**: Calculate the following metrics for the cleaned data:
   - Total number of transactions
   - Total sales amount (sum of all amounts)
   - Average transaction amount (mean, rounded to 2 decimal places)
   - Number of unique customers
   - Date range of the data (earliest and latest sale dates)

5. **Category analysis**: For each product category, calculate:
   - Total sales amount in that category
   - Number of transactions in that category
   - Average transaction amount for that category

## Expected Outputs

You must produce two output files:

1. `/app/cleaned_sales_data.csv` - The cleaned dataset with all quality issues addressed, including:
   - No duplicate rows
   - No missing values
   - Proper datetime format in the `sale_date` column

2. `/app/summary_report.json` - A JSON report containing:
   ```json
   {
     "quality_issues": {
       "missing_values_before": integer,
       "duplicates_found": integer
     },
     "overall_summary": {
       "total_transactions": integer,
       "total_sales_amount": float,
       "average_transaction": float,
       "unique_customers": integer,
       "date_range": {
         "earliest": "YYYY-MM-DD",
         "latest": "YYYY-MM-DD"
       }
     },
     "category_breakdown": {
       "category_name": {
         "total_sales": float,
         "transaction_count": integer,
         "average_amount": float
       }
     }
   }
   ```

## Verification Criteria

The tests will verify:
- Both output files exist at the specified paths
- The CSV file has no missing values and proper datetime format
- The JSON report contains all required fields with correct calculations
- Numerical values are accurate within a small tolerance (0.01)
- The quality issue counts match what was found in the original data