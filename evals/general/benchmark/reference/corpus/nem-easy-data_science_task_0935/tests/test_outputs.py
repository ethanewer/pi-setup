import os
import json
import pandas as pd
import numpy as np
from datetime import datetime

def test_output_files_exist():
    """Verify all required output files were created."""
    assert os.path.exists('/app/reviews_analyzed.csv'), "Missing cleaned dataset"
    assert os.path.exists('/app/summary_report.csv'), "Missing summary report"
    assert os.path.exists('/app/analysis_summary.json'), "Missing JSON summary"

def test_cleaned_dataset_correct():
    """Verify cleaning and sentiment scoring was done correctly."""
    # Load original data
    original_df = pd.read_csv('/app/reviews.csv')
    
    # Load cleaned data
    cleaned_df = pd.read_csv('/app/reviews_analyzed.csv')
    
    # Check that date column is datetime (will fail if not converted)
    cleaned_df['date'] = pd.to_datetime(cleaned_df['date'])
    
    # Check no missing values in review_text or rating
    assert cleaned_df['review_text'].isna().sum() == 0, "Missing values in review_text"
    assert cleaned_df['rating'].isna().sum() == 0, "Missing values in rating"
    
    # Check sentiment score calculation
    expected_scores = []
    for rating in cleaned_df['rating']:
        if rating >= 4:
            expected_scores.append(1)
        elif rating == 3:
            expected_scores.append(0)
        else:
            expected_scores.append(-1)
    
    actual_scores = cleaned_df['sentiment_score'].tolist()
    assert actual_scores == expected_scores, "Sentiment scores calculated incorrectly"

def test_summary_report_correct():
    """Verify summary statistics are computed correctly."""
    # Load cleaned data
    cleaned_df = pd.read_csv('/app/reviews_analyzed.csv')
    
    # Load summary report
    summary_df = pd.read_csv('/app/summary_report.csv')
    
    # Verify required columns exist
    required_cols = ['product_category', 'total_reviews', 'avg_rating', 
                    'positive_count', 'neutral_count', 'negative_count', 'overall_sentiment']
    assert all(col in summary_df.columns for col in required_cols), "Missing columns in summary"
    
    # Verify each category's statistics
    for _, row in summary_df.iterrows():
        category = row['product_category']
        category_data = cleaned_df[cleaned_df['product_category'] == category]
        
        # Check counts
        assert row['total_reviews'] == len(category_data), f"Count mismatch for {category}"
        assert row['avg_rating'] == round(category_data['rating'].mean(), 2), f"Avg rating mismatch for {category}"
        
        # Check sentiment counts
        positive = len(category_data[category_data['sentiment_score'] == 1])
        neutral = len(category_data[category_data['sentiment_score'] == 0])
        negative = len(category_data[category_data['sentiment_score'] == -1])
        
        assert row['positive_count'] == positive, f"Positive count mismatch for {category}"
        assert row['neutral_count'] == neutral, f"Neutral count mismatch for {category}"
        assert row['negative_count'] == negative, f"Negative count mismatch for {category}"
        
        # Check overall sentiment calculation
        expected_sentiment = (positive - negative) / len(category_data) if len(category_data) > 0 else 0
        assert abs(row['overall_sentiment'] - expected_sentiment) < 0.001, f"Sentiment mismatch for {category}"

def test_json_report_correct():
    """Verify JSON summary contains correct information."""
    # Load cleaned data
    cleaned_df = pd.read_csv('/app/reviews_analyzed.csv')
    
    # Load JSON report
    with open('/app/analysis_summary.json', 'r') as f:
        report = json.load(f)
    
    # Check required keys exist
    required_keys = ['total_processed_reviews', 'unique_categories', 
                    'overall_sentiment_score', 'processing_timestamp']
    assert all(key in report for key in required_keys), "Missing keys in JSON report"
    
    # Check values are correct
    assert report['total_processed_reviews'] == len(cleaned_df), "Total reviews count incorrect"
    assert report['unique_categories'] == cleaned_df['product_category'].nunique(), "Unique categories count incorrect"
    
    # Check overall sentiment score calculation
    total_sentiment = cleaned_df['sentiment_score'].sum()
    total_reviews = len(cleaned_df)
    expected_score = total_sentiment / total_reviews if total_reviews > 0 else 0
    
    assert abs(report['overall_sentiment_score'] - expected_score) < 0.001, "Overall sentiment score incorrect"
    
    # Check timestamp is valid ISO format
    try:
        datetime.fromisoformat(report['processing_timestamp'].replace('Z', '+00:00'))
    except ValueError:
        assert False, "Invalid timestamp format in JSON report"