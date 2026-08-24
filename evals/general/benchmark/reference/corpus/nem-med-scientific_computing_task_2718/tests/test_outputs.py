import os
import json
import csv
import numpy as np
from pathlib import Path
import matplotlib.pyplot as plt
from PIL import Image

def test_output_files_exist():
    """Verify all required output files were created."""
    required_files = [
        '/app/output/trajectory.csv',
        '/app/output/summary.json', 
        '/app/output/trajectory.png'
    ]
    for filepath in required_files:
        assert os.path.exists(filepath), f"Missing output file: {filepath}"

def test_csv_format():
    """Verify CSV file has correct format and content."""
    with open('/app/output/trajectory.csv', 'r') as f:
        reader = csv.reader(f)
        header = next(reader)
        
        # Check header
        expected_header = ['time', 'x', 'y', 'z', 'vx', 'vy', 'vz', 'energy']
        assert header == expected_header, f"CSV header mismatch. Expected {expected_header}, got {header}"
        
        # Read all data
        data = list(reader)
        
        # Check we have reasonable number of rows
        assert len(data) >= 10, f"Too few data points: {len(data)}"
        
        # Check data format
        for i, row in enumerate(data):
            assert len(row) == 8, f"Row {i} has {len(row)} columns, expected 8"
            
            # Convert to float and check they're numbers
            for j, val in enumerate(row):
                try:
                    float_val = float(val)
                    assert not np.isnan(float_val), f"NaN value at row {i}, col {j}"
                except ValueError:
                    assert False, f"Non-numeric value '{val}' at row {i}, col {j}"

def test_json_structure():
    """Verify JSON summary has correct structure and types."""
    with open('/app/output/summary.json', 'r') as f:
        summary = json.load(f)
    
    # Check required keys exist
    required_keys = [
        'final_displacement_m', 'max_displacement_m', 'confined',
        'max_kinetic_energy_j', 'energy_conservation_error', 'num_steps'
    ]
    for key in required_keys:
        assert key in summary, f"Missing key in summary: {key}"
    
    # Check data types
    assert isinstance(summary['final_displacement_m'], (int, float)), "final_displacement_m should be numeric"
    assert isinstance(summary['max_displacement_m'], (int, float)), "max_displacement_m should be numeric"
    assert isinstance(summary['confined'], bool), "confined should be boolean"
    assert isinstance(summary['max_kinetic_energy_j'], (int, float)), "max_kinetic_energy_j should be numeric"
    assert isinstance(summary['energy_conservation_error'], (int, float)), "energy_conservation_error should be numeric"
    assert isinstance(summary['num_steps'], int), "num_steps should be integer"
    
    # Check values are reasonable
    assert summary['final_displacement_m'] >= 0, "Displacement cannot be negative"
    assert summary['max_displacement_m'] >= 0, "Max displacement cannot be negative"
    assert summary['max_kinetic_energy_j'] >= 0, "Kinetic energy cannot be negative"
    assert 0 <= summary['energy_conservation_error'] < 0.1, "Energy conservation error unreasonable"
    assert summary['num_steps'] > 0, "Number of steps must be positive"

def test_physics_constraints():
    """Verify physical constraints are satisfied."""
    # Read configuration
    with open('/app/config.json', 'r') as f:
        config = json.load(f)
    
    r0 = config['r0_meters']
    
    # Read trajectory data
    times, xs, ys, zs, vxs, vys, vzs, energies = [], [], [], [], [], [], [], []
    with open('/app/output/trajectory.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            times.append(float(row['time']))
            xs.append(float(row['x']))
            ys.append(float(row['y']))
            zs.append(float(row['z']))
            vxs.append(float(row['vx']))
            vys.append(float(row['vy']))
            vzs.append(float(row['vz']))
            energies.append(float(row['energy']))
    
    # Check velocities are reasonable (less than 1% of speed of light)
    c = 3e8  # speed of light
    max_speed = max(np.sqrt(vx**2 + vy**2 + vz**2) for vx, vy, vz in zip(vxs, vys, vzs))
    assert max_speed < 0.01 * c, f"Speed too high: {max_speed} m/s"
    
    # Check energies are mostly positive (total energy can be negative in potential well)
    # But kinetic energy component should be positive
    m = 9.1093837e-31  # electron mass
    kinetic_energies = [0.5 * m * (vx**2 + vy**2 + vz**2) for vx, vy, vz in zip(vxs, vys, vzs)]
    assert all(k >= 0 for k in kinetic_energies), "Kinetic energy cannot be negative"

def test_plot_exists():
    """Verify plot file exists and is valid PNG."""
    assert os.path.exists('/app/output/trajectory.png'), "Plot file missing"
    
    # Try to open as image
    try:
        img = Image.open('/app/output/trajectory.png')
        img.verify()  # Verify it's a valid image
        assert img.format == 'PNG', "Plot should be PNG format"
    except Exception as e:
        assert False, f"Invalid PNG file: {e}"

def test_energy_conservation():
    """Verify energy conservation error matches calculation from trajectory."""
    with open('/app/output/summary.json', 'r') as f:
        summary = json.load(f)
    
    # Read trajectory data
    energies = []
    with open('/app/output/trajectory.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            energies.append(float(row['energy']))
    
    if len(energies) >= 2:
        # Calculate energy conservation error
        E_initial = energies[0]
        E_final = energies[-1]
        calculated_error = abs((E_final - E_initial) / E_initial) if abs(E_initial) > 1e-15 else abs(E_final - E_initial)
        
        # Check it's close to reported value (allow small floating point differences)
        reported_error = summary['energy_conservation_error']
        assert abs(calculated_error - reported_error) < 1e-10, \
            f"Energy conservation error mismatch: calculated {calculated_error}, reported {reported_error}"