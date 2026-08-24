# Product Review Analysis Pipeline

You are building a data processing pipeline to analyze customer review data from an e-commerce platform. Your task is to transform raw review data into structured insights for business reporting.

## Your Task

Process the product review data and generate two output files:

1. **Read and clean the input CSV file** (`/app/raw_reviews.csv`):
   - The file contains product reviews with the following columns: `review_id`, `product_id`, `customer_id`, `rating`, `review_date`, `review_text`
   - Some rows may have missing values in the `rating` column (shown as empty strings or `null`)

2. **Create category performance summary** (`/app/category_summary.json`):
   - Group reviews by product category (extracted from `product_id` using the format: `CATEGORY_XXX_YYYY` where `XXX` is the category code)
   - For each category, calculate:
     - `total_reviews`: Count of all reviews in that category
     - `average_rating`: Mean rating (rounded to 2 decimal places)
     - `positive_percentage`: Percentage of reviews with rating ≥ 4 (rounded to 1 decimal place)
     - `unique_products`: Number of distinct product IDs in that category
   - Sort categories alphabetically by category code in the output JSON

3. **Generate customer activity report** (`/app/customer_activity.csv`):
   - Group reviews by `customer_id`
   - For each customer, calculate:
     - `review_count`: Total number of reviews submitted
     - `first_review_date`: Earliest review date (in format YYYY-MM-DD)
     - `last_review_date`: Most recent review date (in format YYYY-MM-DD)
     - `avg_rating`: Average rating (rounded to 2 decimal places)
   - Sort customers by `review_count` (descending), then by `avg_rating` (descending)
   - Write to CSV with headers in the order above

## Input Data Format

The input file `/app/raw_reviews.csv` has the following structure:
```
review_id,product_id,customer_id,rating,review_date,review_text
R001,ELEC_001_1001,CUST001,5,2024-01-15,Great product!
R002,BOOK_005_2002,CUST002,,2024-01-16,Missing rating
R003,ELEC_001_1001,CUST003,4,2024-01-17,Good value
R004,BOOK_005_2002,CUST001,3,2024-01-18,Could be better
R005,CLOTH_003_3003,CUST002,5,2024-01-19,Perfect fit!
```

Note:
- Product IDs follow format: `CATEGORY_CODE_SEQUENCE_PRODUCTNUM`
- Categories are: `ELEC` (Electronics), `BOOK` (Books), `CLOTH` (Clothing)
- `rating` is integer from 1-5 (or missing/empty)
- `review_date` is in YYYY-MM-DD format
- Some ratings may be missing (empty string or `null`)

## Expected Outputs

1. `/app/category_summary.json` - JSON object with category codes as keys
   Example structure:
   ```json
   {
     "BOOK": {
       "total_reviews": 10,
       "average_rating": 4.25,
       "positive_percentage": 75.0,
       "unique_products": 5
     },
     "CLOTH": {
       ...
     }
   }
   ```

2. `/app/customer_activity.csv` - CSV file with headers:
   ```
   customer_id,review_count,first_review_date,last_review_date,avg_rating
   CUST001,3,2024-01-15,2024-01-18,4.33
   CUST002,2,2024-01-16,2024-01-19,3.50
   ...
   ```

## Requirements

- Handle missing ratings by excluding them from calculations (don't convert to 0)
- Round numeric values as specified above
- Use consistent date formatting (YYYY-MM-DD)
- Categories should be sorted alphabetically in JSON
- Customers should be sorted by review count (high to low), then average rating (high to low)
- Your code should work correctly with the provided sample data and similar datasets