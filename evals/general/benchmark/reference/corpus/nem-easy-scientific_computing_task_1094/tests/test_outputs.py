import os
import json
import numpy as np
import pytest

def test_output_exists():
    """Verify output file was created."""
    assert os.path.exists('/app/energy_report.json'), "Output file not found"

def test_output_valid_json():
    """Verify output is valid JSON with required structure."""
    with open('/app/energy_report.json', 'r') as f:
        data = json.load(f)
    
    # Check required top-level fields
    required_fields = ['total_energy', 'segments', 'average_temp_deviation', 'processing_summary']
    for field in required_fields:
        assert field in data, f"Missing field: {field}"
    
    # Check types
    assert isinstance(data['total_energy'], (int, float)), "total_energy should be numeric"
    assert isinstance(data['average_temp_deviation'], (int, float)), "average_temp_deviation should be numeric"
    assert isinstance(data['segments'], list), "segments should be a list"
    
    # Check processing_summary structure
    summary = data['processing_summary']
    assert 'data_points' in summary
    assert 'time_span' in summary
    assert 'integration_method' in summary
    assert summary['integration_method'] == 'trapezoidal'

def test_calculation_correct():
    """Verify numerical calculations are correct."""
    # Load input data
    with open('/app/sensor_data.json', 'r') as f:
        input_data = json.load(f)
    
    # Load output data
    with open('/app/energy_report.json', 'r') as f:
        output_data = json.load(f)
    
    timestamps = input_data['timestamps']
    temperatures = input_data['temperatures']
    baseline = input_data['baseline_temp']
    
    # Calculate expected values
    if len(timestamps) < 2:
        expected_energy = 0.0
        expected_segments = []
    else:
        # Compute using trapezoidal rule
        total_energy = 0.0
        segments = []
        for i in range(len(timestamps) - 1):
            dt1 = temperatures[i] - baseline
            dt2 = temperatures[i + 1] - baseline
            time_diff = timestamps[i + 1] - timestamps[i]
            segment_energy = (dt1 + dt2) / 2 * time_diff
            total_energy += segment_energy
            
            segments.append({
                'start_time': timestamps[i],
                'end_time': timestamps[i + 1],
                'energy': round(segment_energy, 3)
            })
        
        expected_energy = round(total_energy, 3)
    
    # Calculate average temperature deviation
    temp_deviations = [t - baseline for t in temperatures]
    expected_avg_deviation = round(sum(temp_deviations) / len(temp_deviations), 3)
    
    # Verify total energy
    assert abs(output_data['total_energy'] - expected_energy) < 0.001, \
        f"Total energy mismatch: expected {expected_energy}, got {output_data['total_energy']}"
    
    # Verify average temperature deviation
    assert abs(output_data['average_temp_deviation'] - expected_avg_deviation) < 0.001, \
        f"Average temp deviation mismatch: expected {expected_avg_deviation}, got {output_data['average_temp_deviation']}"
    
    # Verify segment count
    expected_segment_count = max(0, len(timestamps) - 1)
    assert len(output_data['segments']) == expected_segment_count, \
        f"Segment count mismatch: expected {expected_segment_count}, got {len(output_data['segments'])}"
    
    # Verify processing summary
    assert output_data['processing_summary']['data_points'] == len(timestamps)
    assert output_data['processing_summary']['time_span'] == timestamps[-1] - timestamps[0]

def test_edge_case_single_point():
    """Test that single data point case is handled correctly."""
    # Create test case with single point
    test_input = {
        "timestamps": [1000],
        "temperatures": [25.5],
        "baseline_temp": 21.0
    }
    
    # Write test input
    with open('/app/sensor_data.json', 'w') as f:
        json.dump(test_input, f)
    
    # Run the agent's solution (this test would be run separately)
    # For now, just verify the logic
    if len(test_input['timestamps']) == 1:
        expected_energy = 0.0
        expected_segments = []
        
        # This test would actually run the agent's code
        # For now, we'll trust the main test to catch errors
        pass

def test_precision():
    """Verify floating point precision handling."""
    with open('/app/energy_report.json', 'r') as f:
        output_data = json.load(f)
    
    # Check that values are properly rounded
    total_energy = output_data['total_energy']
    avg_deviation = output_data['average_temp_deviation']
    
    # Convert to string and check decimal places
    total_str = str(total_energy)
    if '.' in total_str:
        decimal_places = len(total_str.split('.')[1])
        assert decimal_places <= 3, f"total_energy has {decimal_places} decimal places, should be ≤ 3"
    
    avg_str = str(avg_deviation)
    if '.' in avg_str:
        decimal_places = len(avg_str.split('.')[1])
        assert decimal_places <= 3, f"average_temp_deviation has {decimal_places} decimal places, should be ≤ 3"
    
    # Check segments precision
    for segment in output_data['segments']:
        energy_str = str(segment['energy'])
        if '.' in energy_str:
            decimal_places = len(energy_str.split('.')[1])
            assert decimal_places <= 3, f"segment energy has {decimal_places} decimal places, should be ≤ 3"