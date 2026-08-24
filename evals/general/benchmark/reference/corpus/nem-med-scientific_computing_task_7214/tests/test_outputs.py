import os
import json
import pandas as pd
import numpy as np
import math

def test_output_files_exist():
    """Verify both output files were created."""
    assert os.path.exists('/app/simulation_results.json'), "simulation_results.json not found"
    assert os.path.exists('/app/sensitivity_analysis.csv'), "sensitivity_analysis.csv not found"

def test_json_valid_and_structured():
    """Verify JSON file is valid and has correct structure."""
    with open('/app/simulation_results.json', 'r') as f:
        data = json.load(f)
    
    # Check structure
    assert 'time_series' in data, "Missing time_series key"
    assert 'final_state' in data, "Missing final_state key"
    
    # Check time series arrays
    ts = data['time_series']
    assert 'time' in ts, "Missing time array"
    assert 'angle' in ts, "Missing angle array"
    assert 'angular_velocity' in ts, "Missing angular_velocity array"
    
    # Check arrays are same length
    assert len(ts['time']) == len(ts['angle']) == len(ts['angular_velocity']), "Time series arrays have different lengths"
    
    # Check final state
    fs = data['final_state']
    assert 'angle' in fs, "Missing final angle"
    assert 'angular_velocity' in fs, "Missing final angular velocity"
    assert 'energy' in fs, "Missing final energy"
    
    # Check numerical validity
    assert len(ts['time']) > 0, "Time series is empty"
    assert ts['time'][0] == 0.0, "Time should start at 0"
    assert ts['time'][-1] > 0, "Time should progress"
    
    # Physical plausibility checks
    assert abs(fs['angle']) < 10*math.pi, "Final angle unreasonably large"
    assert fs['energy'] >= 0, "Energy cannot be negative"

def test_csv_valid_and_structured():
    """Verify CSV file is valid and has correct structure."""
    df = pd.read_csv('/app/sensitivity_analysis.csv')
    
    # Check headers
    expected_headers = ['parameter', 'perturbed_value', 'angle_deviation_percent', 'max_abs_deviation']
    assert list(df.columns) == expected_headers, f"CSV headers incorrect. Expected {expected_headers}, got {list(df.columns)}"
    
    # Check data types
    assert df['parameter'].dtype == object, "Parameter column should be string"
    assert pd.api.types.is_numeric_dtype(df['perturbed_value']), "Perturbed value should be numeric"
    assert pd.api.types.is_numeric_dtype(df['angle_deviation_percent']), "Deviation percent should be numeric"
    assert pd.api.types.is_numeric_dtype(df['max_abs_deviation']), "Max deviation should be numeric"
    
    # Check we have data
    assert len(df) > 0, "CSV file is empty"
    
    # Check perturbations cover expected range
    # Load input parameters to know what to expect
    with open('/app/parameters.json', 'r') as f:
        params = json.load(f)
    
    # Count expected rows: 5 perturbations per parameter
    expected_rows = 5 * len(params['sensitivity'])
    assert len(df) == expected_rows, f"Expected {expected_rows} rows, got {len(df)}"
    
    # Check each parameter appears exactly 5 times
    for param_info in params['sensitivity']:
        param_name = param_info['name']
        param_rows = df[df['parameter'] == param_name]
        assert len(param_rows) == 5, f"Parameter {param_name} should have 5 rows, got {len(param_rows)}"
        
        # Check perturbation range
        base_value = params['base_params'][param_name]
        range_val = param_info['range']
        min_val = base_value - range_val
        max_val = base_value + range_val
        
        perturbed_values = param_rows['perturbed_value'].values
        assert len(perturbed_values) == 5, "Should have 5 perturbed values"
        assert np.allclose(np.linspace(min_val, max_val, 5), sorted(perturbed_values), rtol=1e-3), \
            f"Perturbations for {param_name} not equally spaced in expected range"

def test_numerical_convergence():
    """Verify numerical solution has reasonable properties."""
    with open('/app/simulation_results.json', 'r') as f:
        data = json.load(f)
    
    ts = data['time_series']
    time = np.array(ts['time'])
    angle = np.array(ts['angle'])
    angular_vel = np.array(ts['angular_velocity'])
    
    # Check time steps are uniform (approximately)
    if len(time) > 2:
        dt = np.diff(time)
        assert np.allclose(dt, dt[0], rtol=1e-2), "Time steps not uniform"
    
    # Check derivatives relationship (crude validation)
    # ω ≈ dθ/dt
    if len(angle) > 10:
        numerical_deriv = np.gradient(angle, time)
        # Allow some tolerance due to numerical differentiation
        correlation = np.corrcoef(numerical_deriv, angular_vel)[0,1]
        assert correlation > 0.8, f"Angular velocity doesn't match derivative of angle (corr={correlation})"

def test_sensitivity_consistency():
    """Verify sensitivity results are internally consistent."""
    df = pd.read_csv('/app/sensitivity_analysis.csv')
    
    # For each parameter, deviations should be small for small perturbations
    # and show monotonic trend
    with open('/app/parameters.json', 'r') as f:
        params = json.load(f)
    
    for param_info in params['sensitivity']:
        param_name = param_info['name']
        param_rows = df[df['parameter'] == param_name].sort_values('perturbed_value')
        
        deviations = param_rows['angle_deviation_percent'].values
        
        # Base case (perturbation = 0) should have 0 deviation
        # Find row closest to base value
        base_value = params['base_params'][param_name]
        closest_idx = np.argmin(np.abs(param_rows['perturbed_value'] - base_value))
        assert abs(deviations[closest_idx]) < 1e-2, f"Base case should have near-zero deviation, got {deviations[closest_idx]}"