# Customer Retention Cohort Analysis with Feature Engineering

You are a data scientist at a SaaS company. Your task is to analyze customer retention patterns and build a feature engineering pipeline that identifies at-risk customers before they churn.

## Dataset Overview

You have access to two datasets:
1. **Customer Subscriptions** (`/app/data/subscriptions.csv`): Contains customer subscription events with timestamps
2. **User Activity** (`/app/data/user_activity.csv`): Contains daily user activity metrics

The configuration file (`/app/config/retention_config.json`) specifies analysis parameters including:
- Retention window definitions (7-day, 30-day, 90-day)
- Risk thresholds for at-risk classification
- Required output formats

## Your Task

### Part 1: Data Preparation and Cohort Creation
1. Load the subscription data and create customer cohorts based on their first subscription month
2. For each cohort, calculate retention rates at 7, 30, and 90-day intervals as specified in the config
3. Handle missing activity data by interpolating or using appropriate defaults (document your approach)

### Part 2: Feature Engineering for Churn Prediction
1. Create the following features for each customer:
   - **Usage consistency**: Standard deviation of daily activity over the last 30 days
   - **Engagement trend**: Slope of activity over the last 14 days (using linear regression)
   - **Feature interaction**: Product of usage consistency and engagement trend
   - **Temporal features**: Day of week patterns, weekend vs weekday activity ratio
   
2. Apply the following transformations:
   - Normalize all numerical features to 0-1 range
   - One-hot encode categorical variables (if any)
   - Handle outliers using winsorization (cap at 5th and 95th percentiles)

### Part 3: At-Risk Customer Identification
1. Using the engineered features, identify at-risk customers using these criteria:
   - Engagement trend < -0.5 (strong negative trend)
   - Usage consistency > threshold (high volatility)
   - OR any customer with both metrics in the bottom quartile
   
2. Calculate the following statistics for at-risk customers:
   - False positive rate (customers flagged but didn't churn)
   - Precision of at-risk identification
   - Expected churn rate reduction if intervention succeeds

### Part 4: Automated Reporting
1. Generate a comprehensive JSON report with:
   - Cohort retention rates (7, 30, 90-day)
   - Feature importance ranking (based on correlation with retention)
   - At-risk customer statistics
   - Model performance metrics (if you implement a simple classifier)
   
2. Create visualization files (PNG format) showing:
   - Cohort retention curves
   - Feature distributions for retained vs churned customers
   - Correlation matrix of engineered features

## Expected Outputs

You MUST produce the following files:

1. **`/app/output/retention_analysis.json`** - Main analysis report with:
   ```json
   {
     "cohort_analysis": {
       "cohorts": ["2024-01", "2024-02", ...],
       "retention_rates": {
         "7_day": [0.85, 0.82, ...],
         "30_day": [0.72, 0.68, ...],
         "90_day": [0.55, 0.51, ...]
       }
     },
     "feature_engineering": {
       "features_created": ["usage_consistency", "engagement_trend", ...],
       "feature_importance": {"feature_name": importance_score, ...}
     },
     "risk_analysis": {
       "at_risk_count": 123,
       "precision": 0.75,
       "false_positive_rate": 0.12,
       "potential_churn_reduction": 0.35
     }
   }
   ```

2. **`/app/output/at_risk_customers.csv`** - List of identified at-risk customers:
   ```
   customer_id,subscription_date,risk_score,primary_risk_factor,last_activity_date
   12345,2024-01-15,0.85,engagement_trend,2024-03-20
   ...
   ```

3. **`/app/output/visualizations/`** - Directory containing:
   - `cohort_retention.png` - Line chart of retention curves
   - `feature_distributions.png` - Histograms of key features
   - `correlation_matrix.png` - Heatmap of feature correlations

4. **`/app/output/feature_pipeline.pkl`** - Serialized feature engineering pipeline (using joblib or pickle)

## Verification Criteria

The tests will check:
1. All output files exist in the specified locations
2. JSON report has the correct structure and valid values (all rates between 0-1)
3. At-risk customer CSV has required columns and valid risk scores (0-1)
4. Feature importance scores sum to approximately 1
5. Visualizations are properly saved as PNG files
6. Feature pipeline can be loaded and transforms new data correctly

## Implementation Notes

- Use the configuration values from `/app/config/retention_config.json`
- Handle timezone-naive timestamps (assume UTC)
- Document any assumptions in code comments
- Ensure reproducibility by setting random seeds where needed
- The analysis should complete within 5 minutes on the provided dataset