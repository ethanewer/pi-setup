import os
import json
import pandas as pd
import numpy as np
import pytest

def test_output_files_exist():
    """Verify both output files were created."""
    assert os.path.exists('/app/cleaned_calls.csv'), "Cleaned data file missing"
    assert os.path.exists('/app/summary_report.json'), "Summary report missing"

def test_cleaned_data_quality():
    """Verify cleaned data has no missing values in critical columns."""
    df = pd.read_csv('/app/cleaned_calls.csv')
    
    # Check for missing values in critical columns
    critical_cols = ['call_id', 'duration_minutes', 'customer_rating']
    for col in critical_cols:
        assert df[col].notna().all(), f"Missing values found in {col}"
    
    # Verify data types
    assert pd.api.types.is_string_dtype(df['call_id']), "call_id should be string"
    assert pd.api.types.is_numeric_dtype(df['duration_minutes']), "duration_minutes should be numeric"
    assert pd.api.types.is_numeric_dtype(df['customer_rating']), "customer_rating should be numeric"
    
    # Check date formatting
    assert 'call_date' in df.columns, "call_date column missing"
    # Try to parse as datetime (should not raise error if properly formatted)
    pd.to_datetime(df['call_date'])

def test_summary_report_structure():
    """Verify JSON report has correct structure and data types."""
    with open('/app/summary_report.json', 'r') as f:
        report = json.load(f)
    
    # Check all required keys exist
    required_keys = ['total_calls', 'average_duration', 'average_rating', 
                    'calls_by_issue', 'busiest_day', 'data_quality']
    for key in required_keys:
        assert key in report, f"Missing key in report: {key}"
    
    # Check data types
    assert isinstance(report['total_calls'], int), "total_calls should be integer"
    assert isinstance(report['average_duration'], (int, float)), "average_duration should be numeric"
    assert isinstance(report['average_rating'], (int, float)), "average_rating should be numeric"
    assert isinstance(report['calls_by_issue'], dict), "calls_by_issue should be object/dict"
    assert isinstance(report['busiest_day'], str), "busiest_day should be string"
    assert isinstance(report['data_quality'], dict), "data_quality should be object/dict"
    
    # Check date format
    try:
        pd.to_datetime(report['busiest_day'])
    except:
        pytest.fail(f"busiest_day '{report['busiest_day']}' is not valid date format")
    
    # Check data_quality structure
    assert 'rows_processed' in report['data_quality'], "data_quality missing rows_processed"
    assert 'rows_removed' in report['data_quality'], "data_quality missing rows_removed"
    assert isinstance(report['data_quality']['rows_processed'], int), "rows_processed should be integer"
    assert isinstance(report['data_quality']['rows_removed'], int), "rows_removed should be integer"

def test_statistical_accuracy():
    """Verify computed statistics match expected values from cleaned data."""
    # Load original data to compute expected values
    original_df = pd.read_csv('/app/customer_calls.csv')
    
    # Clean the data as expected
    cleaned_df = original_df.dropna(subset=['call_id', 'duration_minutes', 'customer_rating']).copy()
    cleaned_df['call_date'] = pd.to_datetime(cleaned_df['call_date'])
    
    # Compute expected values
    expected_total = len(cleaned_df)
    expected_avg_duration = round(cleaned_df['duration_minutes'].mean(), 2)
    expected_avg_rating = round(cleaned_df['customer_rating'].mean(), 2)
    
    # Find busiest day
    busiest_date = cleaned_df['call_date'].value_counts().idxmax()
    expected_busiest_day = busiest_date.strftime('%Y-%m-%d')
    
    # Count by issue type
    expected_calls_by_issue = cleaned_df['issue_type'].value_counts().to_dict()
    
    # Load generated report
    with open('/app/summary_report.json', 'r') as f:
        report = json.load(f)
    
    # Compare with tolerance for floating point
    assert report['total_calls'] == expected_total, f"total_calls mismatch: {report['total_calls']} vs {expected_total}"
    assert abs(report['average_duration'] - expected_avg_duration) < 0.01, f"average_duration mismatch: {report['average_duration']} vs {expected_avg_duration}"
    assert abs(report['average_rating'] - expected_avg_rating) < 0.01, f"average_rating mismatch: {report['average_rating']} vs {expected_avg_rating}"
    assert report['busiest_day'] == expected_busiest_day, f"busiest_day mismatch: {report['busiest_day']} vs {expected_busiest_day}"
    
    # Compare calls_by_issue (allow different order)
    assert report['calls_by_issue'] == expected_calls_by_issue, f"calls_by_issue mismatch"

def test_consistency_between_files():
    """Verify summary report matches the cleaned data file."""
    cleaned_df = pd.read_csv('/app/cleaned_calls.csv')
    
    with open('/app/summary_report.json', 'r') as f:
        report = json.load(f)
    
    # Check that report matches cleaned data
    assert len(cleaned_df) == report['total_calls'], "Report total_calls doesn't match cleaned data row count"
    
    # Check average duration from cleaned data matches report
    cleaned_avg_duration = round(cleaned_df['duration_minutes'].mean(), 2)
    assert abs(cleaned_avg_duration - report['average_duration']) < 0.01
    
    # Check busiest day
    cleaned_df['call_date'] = pd.to_datetime(cleaned_df['call_date'])
    busiest_date = cleaned_df['call_date'].value_counts().idxmax().strftime('%Y-%m-%d')
    assert busiest_date == report['busiest_day']