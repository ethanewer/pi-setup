import os
import json
import pandas as pd
import numpy as np
from datetime import datetime

def test_output_files_exist():
    """Verify both output files were created."""
    assert os.path.exists('/app/cleaned_sales_data.csv'), "Cleaned CSV file not found"
    assert os.path.exists('/app/summary_report.json'), "Summary JSON file not found"

def test_csv_quality():
    """Verify the cleaned CSV has no quality issues."""
    df = pd.read_csv('/app/cleaned_sales_data.csv')
    
    # Check for missing values
    assert df.isnull().sum().sum() == 0, "Cleaned CSV contains missing values"
    
    # Check for duplicates
    assert df.duplicated().sum() == 0, "Cleaned CSV contains duplicate rows"
    
    # Check date format
    try:
        pd.to_datetime(df['sale_date'], format='%Y-%m-%d')
    except ValueError:
        assert False, "sale_date column not in YYYY-MM-DD format"
    
    # Check amount column is numeric
    assert pd.api.types.is_numeric_dtype(df['amount']), "amount column should be numeric"

def test_json_structure():
    """Verify JSON report has correct structure and data types."""
    with open('/app/summary_report.json', 'r') as f:
        report = json.load(f)
    
    # Check structure
    assert 'quality_issues' in report
    assert 'overall_summary' in report
    assert 'category_breakdown' in report
    
    # Check data types
    assert isinstance(report['quality_issues']['missing_values_before'], int)
    assert isinstance(report['quality_issues']['duplicates_found'], int)
    assert isinstance(report['overall_summary']['total_transactions'], int)
    assert isinstance(report['overall_summary']['total_sales_amount'], (int, float))
    assert isinstance(report['overall_summary']['average_transaction'], (int, float))
    assert isinstance(report['overall_summary']['unique_customers'], int)
    
    # Check date format
    date_format = '%Y-%m-%d'
    try:
        datetime.strptime(report['overall_summary']['date_range']['earliest'], date_format)
        datetime.strptime(report['overall_summary']['date_range']['latest'], date_format)
    except ValueError:
        assert False, "Dates not in YYYY-MM-DD format"

def test_calculations_accuracy():
    """Verify calculations are accurate."""
    # Load original data to verify quality issue counts
    original_df = pd.read_csv('/app/sales_data.csv')
    
    with open('/app/summary_report.json', 'r') as f:
        report = json.load(f)
    
    # Verify quality issue counts
    missing_before = original_df.isnull().sum().sum()
    duplicates_before = original_df.duplicated().sum()
    
    assert report['quality_issues']['missing_values_before'] == missing_before, \
        f"Missing values count incorrect. Expected: {missing_before}, Got: {report['quality_issues']['missing_values_before']}"
    assert report['quality_issues']['duplicates_found'] == duplicates_before, \
        f"Duplicate count incorrect. Expected: {duplicates_before}, Got: {report['quality_issues']['duplicates_found']}"
    
    # Load cleaned data to verify calculations
    cleaned_df = pd.read_csv('/app/cleaned_sales_data.csv')
    cleaned_df['sale_date'] = pd.to_datetime(cleaned_df['sale_date'])
    
    # Verify overall summary calculations
    total_transactions = len(cleaned_df)
    total_sales = cleaned_df['amount'].sum()
    avg_transaction = cleaned_df['amount'].mean()
    unique_customers = cleaned_df['customer_id'].nunique()
    earliest_date = cleaned_df['sale_date'].min().strftime('%Y-%m-%d')
    latest_date = cleaned_df['sale_date'].max().strftime('%Y-%m-%d')
    
    tolerance = 0.01
    
    assert report['overall_summary']['total_transactions'] == total_transactions, \
        f"Transaction count mismatch. Expected: {total_transactions}"
    assert abs(report['overall_summary']['total_sales_amount'] - total_sales) < tolerance, \
        f"Total sales mismatch. Expected: {total_sales}, Got: {report['overall_summary']['total_sales_amount']}"
    assert abs(report['overall_summary']['average_transaction'] - avg_transaction) < tolerance, \
        f"Average transaction mismatch. Expected: {avg_transaction}, Got: {report['overall_summary']['average_transaction']}"
    assert report['overall_summary']['unique_customers'] == unique_customers, \
        f"Unique customers mismatch. Expected: {unique_customers}"
    assert report['overall_summary']['date_range']['earliest'] == earliest_date, \
        f"Earliest date mismatch. Expected: {earliest_date}"
    assert report['overall_summary']['date_range']['latest'] == latest_date, \
        f"Latest date mismatch. Expected: {latest_date}"
    
    # Verify category breakdown
    for category, stats in report['category_breakdown'].items():
        cat_df = cleaned_df[cleaned_df['category'] == category]
        
        expected_total = cat_df['amount'].sum()
        expected_count = len(cat_df)
        expected_avg = cat_df['amount'].mean() if expected_count > 0 else 0
        
        assert abs(stats['total_sales'] - expected_total) < tolerance, \
            f"Total sales for {category} mismatch. Expected: {expected_total}"
        assert stats['transaction_count'] == expected_count, \
            f"Transaction count for {category} mismatch. Expected: {expected_count}"
        if expected_count > 0:
            assert abs(stats['average_amount'] - expected_avg) < tolerance, \
                f"Average amount for {category} mismatch. Expected: {expected_avg}"

def test_csv_content_matches_report():
    """Verify the CSV data matches the JSON report calculations."""
    cleaned_df = pd.read_csv('/app/cleaned_sales_data.csv')
    cleaned_df['sale_date'] = pd.to_datetime(cleaned_df['sale_date'])
    
    with open('/app/summary_report.json', 'r') as f:
        report = json.load(f)
    
    # Cross-check totals
    assert len(cleaned_df) == report['overall_summary']['total_transactions']
    assert abs(cleaned_df['amount'].sum() - report['overall_summary']['total_sales_amount']) < 0.01
    
    # Check that all categories in CSV are in report
    csv_categories = set(cleaned_df['category'].unique())
    report_categories = set(report['category_breakdown'].keys())
    assert csv_categories == report_categories, \
        f"Categories mismatch. CSV: {csv_categories}, Report: {report_categories}"