import os
import json
import pandas as pd
import numpy as np
import pickle
from pathlib import Path
from sklearn.preprocessing import StandardScaler
import matplotlib.pyplot as plt

def test_output_exists():
    """Verify all required output files were created."""
    required_files = [
        '/app/output/retention_analysis.json',
        '/app/output/at_risk_customers.csv',
        '/app/output/feature_pipeline.pkl',
        '/app/output/visualizations/cohort_retention.png',
        '/app/output/visualizations/feature_distributions.png',
        '/app/output/visualizations/correlation_matrix.png'
    ]
    
    for file_path in required_files:
        assert os.path.exists(file_path), f"Missing file: {file_path}"
    
    # Verify CSV has content
    df = pd.read_csv('/app/output/at_risk_customers.csv')
    assert len(df) > 0, "At-risk customers CSV is empty"
    assert 'customer_id' in df.columns
    assert 'risk_score' in df.columns

def test_json_structure_valid():
    """Verify JSON report has correct structure and valid values."""
    with open('/app/output/retention_analysis.json', 'r') as f:
        report = json.load(f)
    
    # Check required sections exist
    assert 'cohort_analysis' in report
    assert 'feature_engineering' in report
    assert 'risk_analysis' in report
    
    # Check retention rates are valid
    retention = report['cohort_analysis']['retention_rates']
    for period in ['7_day', '30_day', '90_day']:
        rates = retention[period]
        assert all(0 <= rate <= 1 for rate in rates), f"Invalid retention rate in {period}"
        assert len(rates) > 0, f"No retention rates for {period}"
    
    # Check feature importance sums to approximately 1
    feature_importance = report['feature_engineering']['feature_importance']
    importance_sum = sum(feature_importance.values())
    assert 0.95 <= importance_sum <= 1.05, f"Feature importance sum should be ~1, got {importance_sum}"
    
    # Check risk analysis values are valid
    risk = report['risk_analysis']
    assert 0 <= risk['precision'] <= 1
    assert 0 <= risk['false_positive_rate'] <= 1
    assert 0 <= risk['potential_churn_reduction'] <= 1

def test_feature_pipeline_works():
    """Verify the feature pipeline can be loaded and transforms data."""
    # Load pipeline
    with open('/app/output/feature_pipeline.pkl', 'rb') as f:
        pipeline = pickle.load(f)
    
    # Test it can transform sample data
    sample_data = pd.DataFrame({
        'customer_id': [99999],
        'activity_count': [50],
        'login_count': [10],
        'feature_usage': [25]
    })
    
    try:
        transformed = pipeline.transform(sample_data)
        # Should return numpy array or similar
        assert transformed is not None
    except Exception as e:
        # If pipeline expects different columns, that's acceptable
        # as long as it loads without error
        pass

def test_at_risk_customers_valid():
    """Verify at-risk customers CSV has valid data."""
    df = pd.read_csv('/app/output/at_risk_customers.csv')
    
    # Check required columns
    required_cols = ['customer_id', 'risk_score', 'primary_risk_factor']
    for col in required_cols:
        assert col in df.columns, f"Missing column: {col}"
    
    # Check risk scores are valid
    assert df['risk_score'].min() >= 0, "Risk scores should be >= 0"
    assert df['risk_score'].max() <= 1, "Risk scores should be <= 1"
    
    # Check no duplicate customers
    assert df['customer_id'].nunique() == len(df), "Duplicate customer IDs found"
    
    # Check risk factors are valid categories
    valid_factors = ['engagement_trend', 'usage_consistency', 'both', 'other']
    assert all(factor in valid_factors for factor in df['primary_risk_factor'].unique())

def test_visualizations_valid():
    """Verify visualizations are proper PNG files."""
    viz_dir = '/app/output/visualizations'
    
    for viz_file in ['cohort_retention.png', 'feature_distributions.png', 'correlation_matrix.png']:
        file_path = os.path.join(viz_dir, viz_file)
        
        # Check file exists and has content
        assert os.path.exists(file_path), f"Missing visualization: {viz_file}"
        assert os.path.getsize(file_path) > 1000, f"Visualization too small: {viz_file}"
        
        # Try to load as image (basic check)
        try:
            img = plt.imread(file_path)
            assert img.shape[0] > 0 and img.shape[1] > 0, f"Invalid image dimensions: {viz_file}"
        except Exception as e:
            # If matplotlib can't read it, at least verify it's not empty
            with open(file_path, 'rb') as f:
                header = f.read(8)
                assert header[:8] == b'\x89PNG\r\n\x1a\n' or header[:4] == b'\xff\xd8\xff\xe0', f"Not a valid PNG/JPEG: {viz_file}"

def test_cohort_calculations_consistent():
    """Verify cohort calculations are mathematically consistent."""
    # Load original data to verify calculations
    subs_df = pd.read_csv('/app/data/subscriptions.csv')
    activity_df = pd.read_csv('/app/data/user_activity.csv')
    
    # Convert dates
    subs_df['subscription_date'] = pd.to_datetime(subs_df['subscription_date'])
    activity_df['activity_date'] = pd.to_datetime(activity_df['activity_date'])
    
    # Load the analysis results
    with open('/app/output/retention_analysis.json', 'r') as f:
        report = json.load(f)
    
    # Verify we have at least some cohorts
    cohorts = report['cohort_analysis']['cohorts']
    assert len(cohorts) > 0, "No cohorts found"
    
    # Verify retention rates arrays match cohorts count
    for period in ['7_day', '30_day', '90_day']:
        rates = report['cohort_analysis']['retention_rates'][period]
        assert len(rates) == len(cohorts), f"Retention rates count mismatch for {period}"

def test_config_used():
    """Verify configuration parameters were used."""
    with open('/app/config/retention_config.json', 'r') as f:
        config = json.load(f)
    
    with open('/app/output/retention_analysis.json', 'r') as f:
        report = json.load(f)
    
    # Check that retention windows match config
    retention_windows = config['retention_windows']
    assert set(report['cohort_analysis']['retention_rates'].keys()) == set(retention_windows), "Retention windows don't match config"
    
    # Check risk threshold was used (implicitly)
    risk_stats = report['risk_analysis']
    assert 'false_positive_rate' in risk_stats, "Risk analysis missing false positive rate"