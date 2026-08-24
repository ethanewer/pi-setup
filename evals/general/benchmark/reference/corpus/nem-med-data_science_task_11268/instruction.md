# Marketing Campaign Impact Analyzer

You are a data scientist at an e-commerce company. The marketing team recently ran a two-week promotional campaign and wants to understand its impact on sales. Your task is to analyze the campaign data and produce an automated impact report with statistical validation.

## Data Files Available

1. `/app/sales_data.csv` - Daily sales data for the past 90 days
2. `/app/campaign_periods.json` - Campaign timing information
3. `/app/config.yaml` - Analysis configuration parameters

## Your Task

1. **Load and Preprocess Data** (Data loading, transformation)
   - Read the sales data CSV and campaign periods JSON
   - Parse date columns and handle any missing values (drop or impute with forward fill)
   - Create a new column `is_campaign` that marks dates during campaign periods (1 for campaign, 0 otherwise)

2. **Calculate Campaign Metrics** (Statistical aggregation, effect estimation)
   - Compute average daily sales during campaign vs. non-campaign periods
   - Calculate the absolute and percentage lift from campaign
   - Compute 95% confidence intervals for both campaign and non-campaign averages
   - Calculate statistical significance (p-value) using a two-sample t-test

3. **Generate Impact Report** (Data serialization, structured data creation)
   - Create a comprehensive JSON report at `/app/campaign_impact_report.json` with the following structure:
     ```json
     {
       "analysis_date": "YYYY-MM-DD",
       "campaign_periods": ["start_date", "end_date"],
       "metrics": {
         "pre_campaign_avg": number,
         "campaign_avg": number,
         "absolute_lift": number,
         "percentage_lift": number,
         "confidence_intervals": {
           "pre_campaign": [lower, upper],
           "campaign": [lower, upper]
         },
         "statistical_significance": {
           "p_value": number,
           "is_significant": boolean,
           "confidence_level": number
         }
       },
       "data_summary": {
         "total_days": integer,
         "campaign_days": integer,
         "non_campaign_days": integer,
         "missing_values_handled": integer
       },
       "recommendations": ["string"]
     }
     ```
   - Recommendations should be based on the analysis (e.g., "Continue similar campaigns" if significant positive lift)

4. **Create Visualization** (Data transformation, format conversion)
   - Generate a time series plot showing sales with campaign periods highlighted
   - Save as `/app/sales_timeline.png` in PNG format
   - Ensure the plot has proper labels, title, and legend

## Expected Outputs

- `/app/campaign_impact_report.json` - Complete statistical analysis report
- `/app/sales_timeline.png` - Visual representation of sales during campaign

## Validation Criteria

The test suite will verify:
1. Output files exist and are properly formatted
2. Statistical calculations are correct (within tolerance)
3. Confidence intervals are properly computed
4. P-value calculation follows standard statistical methods
5. JSON structure matches the specified schema exactly
6. Recommendations are logically derived from the analysis results

## Important Notes

- The campaign periods in the JSON file may include partial days
- Handle edge cases where sales data might have outliers or anomalies
- Use the configuration parameters from `/app/config.yaml` for confidence level and missing value handling strategy
- Ensure your code is robust to different data formats and potential data quality issues