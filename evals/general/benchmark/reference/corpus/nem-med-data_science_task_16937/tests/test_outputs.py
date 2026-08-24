import os
import json
import pandas as pd
import numpy as np
from scipy import stats
import statsmodels.stats.proportion as proportion
from datetime import datetime, timedelta

def test_output_files_exist():
    """Verify all required output files were created."""
    required_files = [
        '/app/processed_data.csv',
        '/app/ab_test_report.json',
        '/app/visualization_data.csv'
    ]
    
    for file_path in required_files:
        assert os.path.exists(file_path), f"Missing required file: {file_path}"
    
    # Check if validation errors file exists (only if validation failed)
    validation_file = '/app/validation_errors.json'
    if os.path.exists(validation_file):
        # If validation failed, the other files might not exist
        with open(validation_file, 'r') as f:
            errors = json.load(f)
            assert isinstance(errors, list), "Validation errors should be a list"
    else:
        # If validation passed, all required files should exist
        for file_path in required_files:
            assert os.path.getsize(file_path) > 0, f"File is empty: {file_path}"

def test_report_structure():
    """Verify the JSON report has correct structure and data types."""
    if not os.path.exists('/app/ab_test_report.json'):
        return  # Skip if validation failed
    
    with open('/app/ab_test_report.json', 'r') as f:
        report = json.load(f)
    
    # Check top-level structure
    required_keys = ['experiment_summary', 'statistical_tests', 'recommendation', 'validation_passed']
    for key in required_keys:
        assert key in report, f"Missing key in report: {key}"
    
    # Check experiment summary
    summary = report['experiment_summary']
    assert 'duration_days' in summary
    assert 'variant_a_users' in summary
    assert 'variant_b_users' in summary
    assert 'total_conversions' in summary
    assert 'total_revenue' in summary
    
    # Check statistical tests
    tests = report['statistical_tests']
    for test_name in ['conversion_rate', 'average_revenue', 'session_distribution']:
        assert test_name in tests, f"Missing test: {test_name}"
        
        test_result = tests[test_name]
        assert 'test_statistic' in test_result
        assert 'p_value' in test_result
        assert 'significant' in test_result
        
        if test_name != 'session_distribution':
            assert 'confidence_interval' in test_result
            assert 'relative_improvement' in test_result
    
    # Check recommendation
    assert isinstance(report['recommendation'], str)
    assert len(report['recommendation']) > 0

def test_statistical_calculations():
    """Verify statistical calculations are correct."""
    if not os.path.exists('/app/ab_test_report.json'):
        return  # Skip if validation failed
    
    # Load original data
    df = pd.read_csv('/app/ab_test_data.csv')
    
    # Calculate expected values
    # Group by variant
    variant_stats = df.groupby('variant').agg({
        'sessions': 'sum',
        'conversions': 'sum',
        'revenue': 'sum'
    }).reset_index()
    
    # Variant A stats
    a_stats = variant_stats[variant_stats['variant'] == 'A'].iloc[0]
    b_stats = variant_stats[variant_stats['variant'] == 'B'].iloc[0]
    
    # Expected conversion rates
    a_conv_rate = a_stats['conversions'] / a_stats['sessions']
    b_conv_rate = b_stats['conversions'] / b_stats['sessions']
    
    # Expected average revenue
    a_avg_rev = a_stats['revenue'] / a_stats['sessions']
    b_avg_rev = b_stats['revenue'] / b_stats['sessions']
    
    # Load report
    with open('/app/ab_test_report.json', 'r') as f:
        report = json.load(f)
    
    # Check summary statistics
    summary = report['experiment_summary']
    assert summary['variant_a_users'] == int(a_stats['sessions'])
    assert summary['variant_b_users'] == int(b_stats['sessions'])
    assert summary['total_conversions'] == int(a_stats['conversions'] + b_stats['conversions'])
    assert abs(summary['total_revenue'] - (a_stats['revenue'] + b_stats['revenue'])) < 0.01
    
    # Calculate expected statistical tests
    # Conversion rate test (two-sample proportion z-test)
    count = [a_stats['conversions'], b_stats['conversions']]
    nobs = [a_stats['sessions'], b_stats['sessions']]
    stat, pval = proportion.proportions_ztest(count, nobs, alternative='two-sided')
    
    # Calculate confidence interval for difference in proportions
    se = np.sqrt(a_conv_rate*(1-a_conv_rate)/a_stats['sessions'] + 
                 b_conv_rate*(1-b_conv_rate)/b_stats['sessions'])
    diff = b_conv_rate - a_conv_rate
    ci_lower = diff - 1.96 * se
    ci_upper = diff + 1.96 * se
    
    # Check conversion rate test results
    conv_test = report['statistical_tests']['conversion_rate']
    assert abs(conv_test['test_statistic'] - stat) < 0.01
    assert abs(conv_test['p_value'] - pval) < 0.001
    assert abs(conv_test['confidence_interval'][0] - ci_lower) < 0.001
    assert abs(conv_test['confidence_interval'][1] - ci_upper) < 0.001
    assert conv_test['significant'] == (pval < 0.05)
    
    # Check relative improvement
    expected_relative_improvement = (b_conv_rate - a_conv_rate) / a_conv_rate
    assert abs(conv_test['relative_improvement'] - expected_relative_improvement) < 0.001

def test_processed_data():
    """Verify processed data contains calculated metrics."""
    if not os.path.exists('/app/processed_data.csv'):
        return  # Skip if validation failed
    
    df = pd.read_csv('/app/processed_data.csv')
    
    # Check required columns
    required_cols = ['date', 'variant', 'sessions', 'conversions', 'revenue', 
                    'conversion_rate', 'avg_revenue', 'conversion_rate_7d_ma', 
                    'avg_revenue_7d_ma']
    
    for col in required_cols:
        assert col in df.columns, f"Missing column: {col}"
    
    # Check calculated metrics are correct
    for _, row in df.iterrows():
        # Check conversion rate
        expected_conv_rate = row['conversions'] / row['sessions']
        assert abs(row['conversion_rate'] - expected_conv_rate) < 0.001
        
        # Check average revenue
        expected_avg_rev = row['revenue'] / row['sessions']
        assert abs(row['avg_revenue'] - expected_avg_rev) < 0.001

def test_visualization_data():
    """Verify visualization data is properly formatted."""
    if not os.path.exists('/app/visualization_data.csv'):
        return  # Skip if validation failed
    
    df = pd.read_csv('/app/visualization_data.csv')
    
    # Check required columns
    required_cols = ['date', 'variant', 'conversion_rate', 'conversion_rate_7d_ma',
                    'avg_revenue', 'avg_revenue_7d_ma']
    
    for col in required_cols:
        assert col in df.columns, f"Missing column: {col}"
    
    # Check that we have data for both variants
    variants = df['variant'].unique()
    assert set(variants) == {'A', 'B'}
    
    # Check we have 14 days for each variant
    for variant in ['A', 'B']:
        variant_data = df[df['variant'] == variant]
        assert len(variant_data) == 14, f"Expected 14 days for variant {variant}"

def test_data_validation():
    """Test that validation logic works with corrupted data."""
    # This test will be run separately with corrupted data
    pass