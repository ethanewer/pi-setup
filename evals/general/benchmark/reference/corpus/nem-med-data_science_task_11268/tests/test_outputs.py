import os
import json
import yaml
import pandas as pd
import numpy as np
from scipy import stats
import matplotlib.pyplot as plt
from datetime import datetime

def test_output_files_exist():
    """Verify required output files were created."""
    assert os.path.exists('/app/campaign_impact_report.json'), "Report JSON missing"
    assert os.path.exists('/app/sales_timeline.png'), "Visualization PNG missing"

def test_json_structure_valid():
    """Verify JSON report has correct structure and types."""
    with open('/app/campaign_impact_report.json', 'r') as f:
        report = json.load(f)
    
    # Check required top-level keys
    required_keys = ['analysis_date', 'campaign_periods', 'metrics', 'data_summary', 'recommendations']
    for key in required_keys:
        assert key in report, f"Missing key: {key}"
    
    # Check metrics structure
    metrics = report['metrics']
    assert 'pre_campaign_avg' in metrics and isinstance(metrics['pre_campaign_avg'], (int, float))
    assert 'campaign_avg' in metrics and isinstance(metrics['campaign_avg'], (int, float))
    assert 'absolute_lift' in metrics and isinstance(metrics['absolute_lift'], (int, float))
    assert 'percentage_lift' in metrics and isinstance(metrics['percentage_lift'], (int, float))
    assert 'confidence_intervals' in metrics
    assert 'statistical_significance' in metrics
    
    # Check data summary
    summary = report['data_summary']
    assert all(key in summary for key in ['total_days', 'campaign_days', 'non_campaign_days', 'missing_values_handled'])
    
    # Check recommendations is a list
    assert isinstance(report['recommendations'], list)

def test_statistical_calculations():
    """Verify statistical calculations are correct."""
    # Load original data to verify calculations
    sales_data = pd.read_csv('/app/sales_data.csv')
    with open('/app/campaign_periods.json', 'r') as f:
        campaign_data = json.load(f)
    with open('/app/config.yaml', 'r') as f:
        config = yaml.safe_load(f)
    
    # Parse dates
    sales_data['date'] = pd.to_datetime(sales_data['date'])
    
    # Identify campaign periods
    campaign_periods = []
    for period in campaign_data['campaigns']:
        start = pd.to_datetime(period['start_date'])
        end = pd.to_datetime(period['end_date'])
        campaign_periods.append((start, end))
    
    # Mark campaign days
    def is_campaign_day(date):
        return any(start <= date <= end for start, end in campaign_periods)
    
    sales_data['is_campaign'] = sales_data['date'].apply(is_campaign_day).astype(int)
    
    # Handle missing values as specified in config
    if config['missing_values'] == 'drop':
        sales_data = sales_data.dropna()
    elif config['missing_values'] == 'forward_fill':
        sales_data = sales_data.fillna(method='ffill')
    
    # Calculate metrics
    campaign_sales = sales_data[sales_data['is_campaign'] == 1]['sales']
    non_campaign_sales = sales_data[sales_data['is_campaign'] == 0]['sales']
    
    campaign_avg = campaign_sales.mean()
    non_campaign_avg = non_campaign_sales.mean()
    
    # Compare with report
    with open('/app/campaign_impact_report.json', 'r') as f:
        report = json.load(f)
    
    metrics = report['metrics']
    
    # Check calculations within tolerance
    tolerance = 0.01
    assert abs(metrics['campaign_avg'] - campaign_avg) < tolerance, "Campaign average incorrect"
    assert abs(metrics['pre_campaign_avg'] - non_campaign_avg) < tolerance, "Non-campaign average incorrect"
    
    # Check derived metrics
    expected_lift = campaign_avg - non_campaign_avg
    expected_pct_lift = (expected_lift / non_campaign_avg * 100) if non_campaign_avg != 0 else 0
    
    assert abs(metrics['absolute_lift'] - expected_lift) < tolerance, "Absolute lift incorrect"
    assert abs(metrics['percentage_lift'] - expected_pct_lift) < tolerance, "Percentage lift incorrect"
    
    # Check confidence intervals
    conf_level = config['confidence_level']
    n_campaign = len(campaign_sales)
    n_non = len(non_campaign_sales)
    
    if n_campaign > 1 and n_non > 1:
        # Calculate standard errors
        se_campaign = campaign_sales.std() / np.sqrt(n_campaign)
        se_non = non_campaign_sales.std() / np.sqrt(n_non)
        
        # Calculate t-value for confidence level
        t_val = stats.t.ppf((1 + conf_level) / 2, min(n_campaign, n_non) - 1)
        
        # Expected confidence intervals
        ci_campaign_lower = campaign_avg - t_val * se_campaign
        ci_campaign_upper = campaign_avg + t_val * se_campaign
        ci_non_lower = non_campaign_avg - t_val * se_non
        ci_non_upper = non_campaign_avg + t_val * se_non
        
        # Check against report (allow small floating point differences)
        report_ci_campaign = metrics['confidence_intervals']['campaign']
        report_ci_non = metrics['confidence_intervals']['pre_campaign']
        
        assert abs(report_ci_campaign[0] - ci_campaign_lower) < tolerance * 10, "Campaign CI lower bound incorrect"
        assert abs(report_ci_campaign[1] - ci_campaign_upper) < tolerance * 10, "Campaign CI upper bound incorrect"
        assert abs(report_ci_non[0] - ci_non_lower) < tolerance * 10, "Non-campaign CI lower bound incorrect"
        assert abs(report_ci_non[1] - ci_non_upper) < tolerance * 10, "Non-campaign CI upper bound incorrect"
    
    # Check statistical test
    if n_campaign > 1 and n_non > 1:
        t_stat, p_value = stats.ttest_ind(campaign_sales, non_campaign_sales, equal_var=False)
        sig = report['metrics']['statistical_significance']
        
        # P-value should match
        assert abs(sig['p_value'] - p_value) < tolerance, "P-value incorrect"
        
        # Significance flag should be correct
        expected_sig = p_value < (1 - conf_level)
        assert sig['is_significant'] == expected_sig, "Significance flag incorrect"

def test_visualization_exists():
    """Verify visualization file is valid PNG."""
    # Check file size is reasonable (not empty)
    assert os.path.getsize('/app/sales_timeline.png') > 1000, "PNG file too small"
    
    # Try to open with matplotlib to verify it's a valid image
    try:
        img = plt.imread('/app/sales_timeline.png')
        assert img.shape[2] == 4 or img.shape[2] == 3, "Invalid PNG dimensions"
    except Exception as e:
        assert False, f"Invalid PNG file: {e}"

def test_recommendations_logical():
    """Verify recommendations are logically derived from analysis."""
    with open('/app/campaign_impact_report.json', 'r') as f:
        report = json.load(f)
    
    metrics = report['metrics']
    sig = metrics['statistical_significance']
    recommendations = report['recommendations']
    
    # Check that recommendations exist
    assert len(recommendations) > 0, "No recommendations provided"
    
    # Check that recommendations make sense given the results
    if sig['is_significant'] and metrics['percentage_lift'] > 0:
        # Should recommend continuing or expanding
        positive_keywords = ['continue', 'expand', 'increase', 'successful', 'effective']
        assert any(keyword in ' '.join(recommendations).lower() for keyword in positive_keywords), \
               "Should recommend positive action for significant positive lift"
    elif sig['is_significant'] and metrics['percentage_lift'] < 0:
        # Should recommend stopping or revising
        negative_keywords = ['stop', 'revise', 'reconsider', 'negative', 'ineffective']
        assert any(keyword in ' '.join(recommendations).lower() for keyword in negative_keywords), \
               "Should recommend caution for significant negative lift"

def test_data_summary_accurate():
    """Verify data summary counts are accurate."""
    # Load and process data as in test_statistical_calculations
    sales_data = pd.read_csv('/app/sales_data.csv')
    with open('/app/campaign_periods.json', 'r') as f:
        campaign_data = json.load(f)
    
    sales_data['date'] = pd.to_datetime(sales_data['date'])
    
    campaign_periods = []
    for period in campaign_data['campaigns']:
        start = pd.to_datetime(period['start_date'])
        end = pd.to_datetime(period['end_date'])
        campaign_periods.append((start, end))
    
    def is_campaign_day(date):
        return any(start <= date <= end for start, end in campaign_periods)
    
    sales_data['is_campaign'] = sales_data['date'].apply(is_campaign_day).astype(int)
    
    with open('/app/campaign_impact_report.json', 'r') as f:
        report = json.load(f)
    
    summary = report['data_summary']
    
    # Check counts
    assert summary['total_days'] == len(sales_data), "Total days count incorrect"
    assert summary['campaign_days'] == (sales_data['is_campaign'] == 1).sum(), "Campaign days count incorrect"
    assert summary['non_campaign_days'] == (sales_data['is_campaign'] == 0).sum(), "Non-campaign days count incorrect"