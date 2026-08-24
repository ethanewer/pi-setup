import os
import json
import csv
import pandas as pd
from datetime import datetime

def test_output_files_exist():
    """Verify both output files were created."""
    assert os.path.exists('/app/category_summary.json'), "category_summary.json not found"
    assert os.path.exists('/app/customer_activity.csv'), "customer_activity.csv not found"

def test_category_summary_format():
    """Verify category summary JSON has correct structure and data."""
    with open('/app/category_summary.json', 'r') as f:
        data = json.load(f)
    
    # Check expected categories exist
    expected_categories = ['BOOK', 'CLOTH', 'ELEC']
    assert all(cat in data for cat in expected_categories), f"Missing categories. Found: {list(data.keys())}"
    
    # Check each category has required fields
    required_fields = ['total_reviews', 'average_rating', 'positive_percentage', 'unique_products']
    for category, values in data.items():
        for field in required_fields:
            assert field in values, f"Missing field {field} in category {category}"
    
    # Check categories are sorted alphabetically
    categories = list(data.keys())
    assert categories == sorted(categories), f"Categories not sorted alphabetically: {categories}"
    
    # Verify specific values from sample data
    assert data['BOOK']['total_reviews'] == 2
    assert data['BOOK']['unique_products'] == 1
    assert round(data['BOOK']['average_rating'], 2) == 3.0  # Only one rating: 3
    assert data['BOOK']['positive_percentage'] == 0.0  # Rating 3 is not positive (≥4)
    
    assert data['CLOTH']['total_reviews'] == 1
    assert data['CLOTH']['unique_products'] == 1
    assert data['CLOTH']['average_rating'] == 5.0
    assert data['CLOTH']['positive_percentage'] == 100.0
    
    assert data['ELEC']['total_reviews'] == 2
    assert data['ELEC']['unique_products'] == 1
    assert round(data['ELEC']['average_rating'], 2) == 4.5  # Ratings: 5 and 4
    assert data['ELEC']['positive_percentage'] == 100.0

def test_customer_activity_format():
    """Verify customer activity CSV has correct format and data."""
    # Read CSV
    df = pd.read_csv('/app/customer_activity.csv')
    
    # Check columns
    expected_columns = ['customer_id', 'review_count', 'first_review_date', 'last_review_date', 'avg_rating']
    assert list(df.columns) == expected_columns, f"Columns don't match: {list(df.columns)}"
    
    # Check data types
    assert df['review_count'].dtype == 'int64'
    assert df['avg_rating'].dtype == 'float64'
    
    # Check date format
    for date_col in ['first_review_date', 'last_review_date']:
        for date_str in df[date_col]:
            try:
                datetime.strptime(date_str, '%Y-%m-%d')
            except ValueError:
                assert False, f"Invalid date format: {date_str}"
    
    # Check sorting: review_count descending, then avg_rating descending
    for i in range(len(df) - 1):
        row1 = df.iloc[i]
        row2 = df.iloc[i + 1]
        assert row1['review_count'] >= row2['review_count'], "Not sorted by review_count descending"
        if row1['review_count'] == row2['review_count']:
            assert row1['avg_rating'] >= row2['avg_rating'], "Not sorted by avg_rating when review_count equal"
    
    # Verify specific data from sample
    # CUST001 should be first (2 reviews)
    assert df.iloc[0]['customer_id'] == 'CUST001'
    assert df.iloc[0]['review_count'] == 2
    assert df.iloc[0]['first_review_date'] == '2024-01-15'
    assert df.iloc[0]['last_review_date'] == '2024-01-18'
    assert round(df.iloc[0]['avg_rating'], 2) == 4.0  # Ratings: 5 and 3
    
    # CUST002 should be second (2 reviews but one missing rating, so avg_rating lower)
    assert df.iloc[1]['customer_id'] == 'CUST002'
    assert df.iloc[1]['review_count'] == 2
    assert round(df.iloc[1]['avg_rating'], 2) == 5.0  # Only one valid rating: 5
    
    # CUST003 should be third (1 review)
    assert df.iloc[2]['customer_id'] == 'CUST003'
    assert df.iloc[2]['review_count'] == 1
    assert df.iloc[2]['avg_rating'] == 4.0

def test_missing_rating_handling():
    """Verify missing ratings are properly excluded from calculations."""
    # Read the raw data to check missing rating handling
    df_raw = pd.read_csv('/app/raw_reviews.csv')
    
    # Find rows with missing ratings
    missing_ratings = df_raw['rating'].isna() | (df_raw['rating'] == '')
    
    # Check that CUST002 has one review with missing rating and one with rating 5
    cust002_reviews = df_raw[df_raw['customer_id'] == 'CUST002']
    valid_ratings = cust002_reviews['rating'].dropna()
    valid_ratings = valid_ratings[valid_ratings != '']
    assert len(valid_ratings) == 1
    assert float(valid_ratings.iloc[0]) == 5.0
    
    # Verify this is reflected in customer activity (avg_rating should be 5.0, not 2.5)
    df_activity = pd.read_csv('/app/customer_activity.csv')
    cust002_row = df_activity[df_activity['customer_id'] == 'CUST002'].iloc[0]
    assert cust002_row['avg_rating'] == 5.0, "Missing rating should not be counted as 0"