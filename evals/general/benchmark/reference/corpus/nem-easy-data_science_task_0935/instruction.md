# Customer Review Sentiment Analyzer

You are a data scientist at an e-commerce company. Your manager has asked you to analyze customer review data to understand sentiment patterns across different product categories.

## Your Task

Process the customer reviews dataset at `/app/reviews.csv` and perform the following analysis:

1. **Load and Clean Data**:
   - Read the CSV file into a pandas DataFrame
   - Remove any rows where the 'review_text' or 'rating' column has missing values
   - Convert the 'date' column to datetime format (format: YYYY-MM-DD)

2. **Calculate Basic Sentiment Metrics**:
   - Create a new column 'sentiment_score' where:
     - Positive review: rating >= 4 → score = 1
     - Neutral review: rating = 3 → score = 0
     - Negative review: rating <= 2 → score = -1
   - For each product category, calculate:
     - Total number of reviews
     - Average rating (rounded to 2 decimal places)
     - Sentiment distribution (counts of positive, neutral, negative)
     - Overall sentiment score = (positive_count - negative_count) / total_reviews

3. **Generate Summary Report**:
   - Create a summary DataFrame with columns:
     - 'product_category'
     - 'total_reviews'
     - 'avg_rating'
     - 'positive_count'
     - 'neutral_count'
     - 'negative_count'
     - 'overall_sentiment'
   - Sort the summary by 'total_reviews' in descending order

4. **Save Outputs**:
   - Save the cleaned dataset with sentiment scores to `/app/reviews_analyzed.csv`
   - Save the summary report to `/app/summary_report.csv`
   - Create a JSON report at `/app/analysis_summary.json` containing:
     - "total_processed_reviews": total number of reviews after cleaning
     - "unique_categories": number of unique product categories
     - "overall_sentiment_score": weighted average of all sentiment scores
     - "processing_timestamp": current timestamp in ISO format

## Expected Outputs

- `/app/reviews_analyzed.csv`: CSV file with all original columns plus 'sentiment_score' column
- `/app/summary_report.csv`: CSV file with the 7 columns specified above
- `/app/analysis_summary.json`: JSON file with the 4 key-value pairs specified above

## Test Expectations

The tests will verify:
1. All three output files exist with correct names and formats
2. The cleaned dataset has the correct number of rows after removing missing values
3. Sentiment scores are correctly calculated according to the rules
4. Summary statistics are computed correctly for each category
5. JSON report contains all required fields with correct data types