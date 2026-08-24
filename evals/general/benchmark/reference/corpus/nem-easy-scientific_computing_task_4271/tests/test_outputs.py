import os
import json
import numpy as np
import pytest

def test_output_exists():
    """Verify output file was created."""
    assert os.path.exists('/app/integration_results.json'), "Output file not found"

def test_output_format():
    """Verify output file has correct JSON format and structure."""
    try:
        with open('/app/integration_results.json', 'r') as f:
            result = json.load(f)
    except json.JSONDecodeError:
        pytest.fail("Output file is not valid JSON")
    
    # Check required keys
    required_keys = ['total_integral', 'mean_value', 'time_weighted_average', 
                    'total_time_span', 'data_points']
    for key in required_keys:
        assert key in result, f"Missing key: {key}"
    
    # Check types
    assert isinstance(result['total_integral'], (int, float)), "total_integral should be numeric"
    assert isinstance(result['mean_value'], (int, float)), "mean_value should be numeric"
    assert isinstance(result['time_weighted_average'], (int, float)), "time_weighted_average should be numeric"
    assert isinstance(result['total_time_span'], (int, float)), "total_time_span should be numeric"
    assert isinstance(result['data_points'], int), "data_points should be integer"

def test_output_correctness():
    """Verify the integration calculations are correct."""
    # Read input data
    with open('/app/measurements.json', 'r') as f:
        data = json.load(f)
    
    # Read output
    with open('/app/integration_results.json', 'r') as f:
        result = json.load(f)
    
    # Extract timestamps and values
    timestamps = [point['timestamp'] for point in data]
    values = [point['value'] for point in data]
    
    # Calculate expected values using numpy for verification
    if len(data) > 1:
        # Trapezoidal rule
        dt = np.diff(timestamps)
        avg_values = 0.5 * (np.array(values[:-1]) + np.array(values[1:]))
        expected_integral = np.sum(avg_values * dt)
    else:
        expected_integral = 0.0
    
    expected_mean = np.mean(values)
    expected_time_span = timestamps[-1] - timestamps[0] if len(timestamps) > 1 else 0
    expected_time_weighted = expected_integral / expected_time_span if expected_time_span > 0 else 0
    
    # Check with tolerance
    tolerance = 1e-4  # For rounding to 4 decimal places
    
    assert abs(result['total_integral'] - expected_integral) < tolerance, \
        f"Integration incorrect. Expected {expected_integral}, got {result['total_integral']}"
    
    assert abs(result['mean_value'] - expected_mean) < tolerance, \
        f"Mean value incorrect. Expected {expected_mean}, got {result['mean_value']}"
    
    assert abs(result['total_time_span'] - expected_time_span) < tolerance, \
        f"Time span incorrect. Expected {expected_time_span}, got {result['total_time_span']}"
    
    if expected_time_span > 0:
        assert abs(result['time_weighted_average'] - expected_time_weighted) < tolerance, \
            f"Time-weighted average incorrect. Expected {expected_time_weighted}, got {result['time_weighted_average']}"
    
    assert result['data_points'] == len(data), \
        f"Data points count incorrect. Expected {len(data)}, got {result['data_points']}"