# A/B Test Analysis with Multiple Metrics and Automated Reporting

You are a data scientist at a tech company that recently ran an A/B test for a new website feature. The experiment ran for 14 days with two variants: Control (A) and Treatment (B). The team collected daily metrics but needs a comprehensive statistical analysis to determine if the treatment had a significant effect.

## Your Task

Analyze the A/B test data and generate a complete statistical report with the following steps:

1. **Load and Validate Data**: 
   - Read the experiment data from `/app/ab_test_data.csv`
   - Validate that the data meets quality requirements:
     - No missing values in key columns (date, variant, sessions, conversions, revenue)
     - All variants are either 'A' or 'B'
     - Date range spans exactly 14 days
   - If validation fails, output an error report to `/app/validation_errors.json`

2. **Calculate Daily Metrics**:
   - Compute daily conversion rate (conversions/sessions) for each variant
   - Compute daily average revenue per user (revenue/sessions) for each variant
   - Calculate 7-day moving averages for both metrics to smooth daily volatility
   - Save the processed data with these new metrics to `/app/processed_data.csv`

3. **Statistical Testing**:
   - Perform three statistical tests comparing variant A vs B:
     a. **Conversion Rate**: Two-sample proportion z-test
     b. **Average Revenue**: Two-sample t-test (assume unequal variance)
     c. **Total Sessions**: Chi-square test for independence
   - For each test, calculate:
     - Test statistic
     - P-value
     - 95% confidence interval for the difference (B - A)
     - Statistical significance at α=0.05

4. **Generate Comprehensive Report**:
   - Create a JSON report at `/app/ab_test_report.json` with this structure:
     ```json
     {
       "experiment_summary": {
         "duration_days": 14,
         "variant_a_users": integer,
         "variant_b_users": integer,
         "total_conversions": integer,
         "total_revenue": float
       },
       "statistical_tests": {
         "conversion_rate": {
           "test_statistic": float,
           "p_value": float,
           "confidence_interval": [float, float],
           "significant": boolean,
           "relative_improvement": float
         },
         "average_revenue": {
           "test_statistic": float,
           "p_value": float,
           "confidence_interval": [float, float],
           "significant": boolean,
           "relative_improvement": float
         },
         "session_distribution": {
           "test_statistic": float,
           "p_value": float,
           "significant": boolean
         }
       },
       "recommendation": "string explaining whether to implement the change",
       "validation_passed": boolean
     }
     ```
   - The recommendation should be based on:
     - Statistical significance of primary metrics (conversion rate and revenue)
     - Practical significance (relative improvement > 1%)
     - Consistency of results

5. **Create Visualization Data**:
   - Generate a CSV file at `/app/visualization_data.csv` with these columns:
     - `date`: The day of the experiment
     - `variant`: 'A' or 'B'
     - `conversion_rate`: Daily conversion rate
     - `conversion_rate_7d_ma`: 7-day moving average
     - `avg_revenue`: Daily average revenue per user
     - `avg_revenue_7d_ma`: 7-day moving average

## Expected Outputs

The following files must be created:

1. `/app/processed_data.csv` - CSV file with original data plus computed metrics
2. `/app/ab_test_report.json` - Complete statistical report in JSON format
3. `/app/visualization_data.csv` - Data formatted for visualization
4. `/app/validation_errors.json` - Only if validation fails, with error details

## Test Verification

The automated tests will check:
1. **File existence**: All required output files exist with correct formats
2. **Statistical correctness**: Test statistics and p-values are computed correctly (within tolerance)
3. **Data validation**: Validation logic correctly identifies data quality issues
4. **Report completeness**: All required fields in JSON report are present with correct types
5. **Recommendation logic**: The recommendation aligns with statistical results

## Notes

- Use appropriate statistical libraries (scipy, statsmodels, or numpy)
- Handle edge cases like zero sessions or conversions
- The relative improvement should be calculated as (B_metric - A_metric) / A_metric
- Confidence intervals should be for the difference B - A