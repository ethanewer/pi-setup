import os
import json
import csv
import numpy as np
import pytest
from scipy.integrate import solve_ivp

def load_data():
    """Load the test data."""
    with open('/app/experiment_data.json', 'r') as f:
        return json.load(f)

def test_output_files_exist():
    """Verify output files were created."""
    assert os.path.exists('/app/estimated_parameters.json'), "JSON output missing"
    assert os.path.exists('/app/simulation_results.csv'), "CSV output missing"

def test_json_structure():
    """Verify JSON has correct structure and keys."""
    with open('/app/estimated_parameters.json', 'r') as f:
        data = json.load(f)
    
    required_keys = ['mass_kg', 'damping_coefficient', 'spring_constant', 
                     'final_loss', 'iterations']
    
    for key in required_keys:
        assert key in data, f"Missing key: {key}"
        assert isinstance(data[key], (int, float)), f"Key {key} must be numeric"

def test_csv_structure():
    """Verify CSV has correct headers and data."""
    with open('/app/simulation_results.csv', 'r') as f:
        reader = csv.reader(f)
        rows = list(reader)
    
    assert len(rows) > 1, "CSV must have header and data"
    
    # Check headers
    expected_headers = ['time', 'measured_position', 'simulated_position', 
                       'simulated_velocity', 'absolute_error']
    assert rows[0] == expected_headers, f"Headers mismatch. Expected {expected_headers}, got {rows[0]}"
    
    # Check data rows
    data_rows = rows[1:]
    assert len(data_rows) >= 10, "Should have at least 10 data points"
    
    # Check numeric values in first data row
    first_row = data_rows[0]
    assert len(first_row) == 5, "Each row must have 5 columns"
    
    for value in first_row:
        try:
            float(value)
        except ValueError:
            pytest.fail(f"Non-numeric value in CSV: {value}")

def test_parameter_quality():
    """Verify parameters produce reasonable simulation."""
    # Load test data
    test_data = load_data()
    measurements = test_data['measurements']
    x0 = test_data['initial_conditions']['x0']
    v0 = test_data['initial_conditions']['v0']
    
    # Load estimated parameters
    with open('/app/estimated_parameters.json', 'r') as f:
        params = json.load(f)
    
    m = params['mass_kg']
    b = params['damping_coefficient']
    k = params['spring_constant']
    
    # Define the ODE function for scipy comparison
    def oscillator_ode(t, y):
        x, v = y
        dxdt = v
        dvdt = -(b * v + k * x) / m
        return [dxdt, dvdt]
    
    # Solve with scipy for reference
    t_span = (0, max(m['time'] for m in measurements))
    t_eval = [m['time'] for m in measurements]
    
    sol = solve_ivp(oscillator_ode, t_span, [x0, v0], 
                    t_eval=t_eval, method='RK45', rtol=1e-8, atol=1e-10)
    
    # Calculate error against measurements
    measured_positions = np.array([m['position'] for m in measurements])
    simulated_positions = sol.y[0]
    
    rmse = np.sqrt(np.mean((measured_positions - simulated_positions)**2))
    
    # The solution should have RMSE < 0.05 (as specified in prompt)
    assert rmse < 0.05, f"RMSE {rmse:.4f} exceeds tolerance 0.05"
    
    # Loss in JSON should be close to MSE
    mse = np.mean((measured_positions - simulated_positions)**2)
    assert abs(params['final_loss'] - mse) < 0.01, "Reported loss doesn't match actual MSE"

def test_physical_plausibility():
    """Verify parameters are physically plausible."""
    with open('/app/estimated_parameters.json', 'r') as f:
        params = json.load(f)
    
    m = params['mass_kg']
    b = params['damping_coefficient']
    k = params['spring_constant']
    
    # All parameters should be positive
    assert m > 0, "Mass must be positive"
    assert b >= 0, "Damping coefficient cannot be negative"
    assert k > 0, "Spring constant must be positive"
    
    # Check damping ratio
    critical_damping = 2 * np.sqrt(m * k)
    damping_ratio = b / critical_damping
    
    # System should be underdamped (typical for oscillatory behavior)
    # But allow for critical/overdamped within reasonable bounds
    assert damping_ratio < 2.0, f"Damping ratio {damping_ratio:.3f} is unrealistically high"

def test_csv_consistency():
    """Verify CSV data is internally consistent."""
    with open('/app/simulation_results.csv', 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    
    test_data = load_data()
    measurement_dict = {m['time']: m['position'] for m in test_data['measurements']}
    
    for row in rows:
        t = float(row['time'])
        measured = float(row['measured_position'])
        simulated = float(row['simulated_position'])
        velocity = float(row['simulated_velocity'])
        error = float(row['absolute_error'])
        
        # Check error calculation
        assert abs(error - abs(measured - simulated)) < 1e-10, \
            f"Absolute error calculation wrong at t={t}"
        
        # Check measured position matches input data
        if abs(t - round(t, 2)) < 1e-6:  # Times are at 0.01 increments
            expected_measured = measurement_dict.get(round(t, 2))
            if expected_measured is not None:
                assert abs(measured - expected_measured) < 1e-10, \
                    f"Measured position mismatch at t={t}"