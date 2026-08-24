import os
import json
import numpy as np
import pandas as pd
import pytest

def test_output_files_exist():
    """Verify both output files were created."""
    assert os.path.exists('/app/trajectory.csv'), "trajectory.csv not found"
    assert os.path.exists('/app/summary.json'), "summary.json not found"

def test_csv_format():
    """Verify CSV file has correct format and structure."""
    # Read CSV
    df = pd.read_csv('/app/trajectory.csv')
    
    # Check columns
    assert list(df.columns) == ['time_step', 'count_A', 'count_B'], "CSV columns incorrect"
    
    # Check data types
    assert df['time_step'].dtype in [np.int64, np.int32, int], "time_step should be integer"
    assert df['count_A'].dtype in [np.int64, np.int32, int], "count_A should be integer"
    assert df['count_B'].dtype in [np.int64, np.int32, int], "count_B should be integer"
    
    # Read parameters to verify row count
    with open('/app/parameters.json', 'r') as f:
        params = json.load(f)
    
    expected_rows = params['time_steps'] + 1  # includes initial state
    assert len(df) == expected_rows, f"Expected {expected_rows} rows, got {len(df)}"
    
    # Check time steps are sequential
    assert list(df['time_step']) == list(range(expected_rows)), "Time steps not sequential"

def test_counts_sum_to_N():
    """Verify counts always sum to total molecules N."""
    df = pd.read_csv('/app/trajectory.csv')
    
    with open('/app/parameters.json', 'r') as f:
        params = json.load(f)
    
    N = params['N']
    
    # Check every row
    for i, row in df.iterrows():
        total = row['count_A'] + row['count_B']
        assert total == N, f"Row {i}: counts sum to {total}, expected {N}"

def test_initial_conditions():
    """Verify initial counts match parameters."""
    df = pd.read_csv('/app/trajectory.csv')
    
    with open('/app/parameters.json', 'r') as f:
        params = json.load(f)
    
    # Check first row (time_step 0)
    first_row = df.iloc[0]
    assert first_row['count_A'] == params['initial_A'], "Initial count_A incorrect"
    assert first_row['count_B'] == params['N'] - params['initial_A'], "Initial count_B incorrect"

def test_json_structure():
    """Verify JSON file has correct structure and content."""
    with open('/app/summary.json', 'r') as f:
        summary = json.load(f)
    
    # Check top-level structure
    assert 'parameters' in summary, "Missing 'parameters' in JSON"
    assert 'results' in summary, "Missing 'results' in JSON"
    
    # Check parameters match input
    with open('/app/parameters.json', 'r') as f:
        params = json.load(f)
    
    for key in ['N', 'p_AB', 'p_BA', 'initial_A', 'time_steps', 'seed']:
        assert summary['parameters'][key] == params[key], f"Parameter {key} doesn't match input"
    
    # Check results structure
    results = summary['results']
    assert 'final_A' in results, "Missing 'final_A' in results"
    assert 'final_B' in results, "Missing 'final_B' in results"
    assert 'equilibrium_estimate' in results, "Missing 'equilibrium_estimate' in results"
    
    # Check data types
    assert isinstance(results['final_A'], int), "final_A should be integer"
    assert isinstance(results['final_B'], int), "final_B should be integer"
    assert isinstance(results['equilibrium_estimate'], float), "equilibrium_estimate should be float"
    
    # Check final counts sum to N
    assert results['final_A'] + results['final_B'] == params['N'], "Final counts don't sum to N"

def test_equilibrium_estimate():
    """Verify equilibrium estimate is correctly computed."""
    # Read data
    df = pd.read_csv('/app/trajectory.csv')
    
    with open('/app/summary.json', 'r') as f:
        summary = json.load(f)
    
    with open('/app/parameters.json', 'r') as f:
        params = json.load(f)
    
    equilibrium_estimate = summary['results']['equilibrium_estimate']
    
    # Calculate what the estimate should be
    time_steps = params['time_steps']
    last_fraction = max(1, int(time_steps * 0.1))  # Last 10%, at least 1
    
    last_rows = df.tail(last_fraction)
    fractions = last_rows['count_A'] / params['N']
    expected_estimate = round(fractions.mean(), 3)
    
    # Allow small floating point differences
    assert abs(equilibrium_estimate - expected_estimate) < 0.001, \
        f"Equilibrium estimate incorrect. Expected {expected_estimate}, got {equilibrium_estimate}"

def test_reproducibility():
    """Verify simulation is reproducible with the same seed."""
    # This test runs a simple check that the simulation is deterministic
    with open('/app/parameters.json', 'r') as f:
        params = json.load(f)
    
    # Read the final state from output
    with open('/app/summary.json', 'r') as f:
        summary1 = json.load(f)
    
    final_A1 = summary1['results']['final_A']
    
    # Note: We can't actually re-run the simulation here since we're in test environment
    # But we can verify that the CSV data is internally consistent
    df = pd.read_csv('/app/trajectory.csv')
    
    # Verify the last row of CSV matches the JSON final counts
    last_row = df.iloc[-1]
    assert last_row['count_A'] == final_A1, "CSV final count doesn't match JSON final_A"
    assert last_row['count_B'] == summary1['results']['final_B'], "CSV final count doesn't match JSON final_B"

def test_probability_range():
    """Verify counts stay within valid ranges."""
    df = pd.read_csv('/app/trajectory.csv')
    
    with open('/app/parameters.json', 'r') as f:
        params = json.load(f)
    
    N = params['N']
    
    # Check all counts are between 0 and N
    assert (df['count_A'] >= 0).all(), "count_A has negative values"
    assert (df['count_A'] <= N).all(), "count_A exceeds N"
    assert (df['count_B'] >= 0).all(), "count_B has negative values"
    assert (df['count_B'] <= N).all(), "count_B exceeds N"