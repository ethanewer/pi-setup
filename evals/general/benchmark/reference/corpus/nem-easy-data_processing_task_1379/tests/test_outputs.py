import os
import json
import datetime
import csv
from decimal import Decimal, ROUND_HALF_UP

def test_output_exists():
    """Verify output file was created."""
    assert os.path.exists('/app/electronics_summary.json'), "Output file not found"

def test_output_valid_json():
    """Verify output is valid JSON."""
    try:
        with open('/app/electronics_summary.json', 'r') as f:
            data = json.load(f)
        assert isinstance(data, dict), "Output should be a JSON object"
    except json.JSONDecodeError as e:
        assert False, f"Invalid JSON: {e}"

def test_output_structure():
    """Verify output has correct structure."""
    with open('/app/electronics_summary.json', 'r') as f:
        data = json.load(f)
    
    # Check required top-level keys
    required_keys = ['category', 'total_products', 'summary_date', 'products']
    for key in required_keys:
        assert key in data, f"Missing required key: {key}"
    
    # Check category
    assert data['category'] == 'Electronics', f"Category should be 'Electronics', got {data['category']}"
    
    # Check summary_date format
    try:
        datetime.datetime.strptime(data['summary_date'], '%Y-%m-%d')
    except ValueError:
        assert False, f"Invalid date format: {data['summary_date']}"
    
    # Check products is a list
    assert isinstance(data['products'], list), "Products should be a list"
    
    # Check each product has required fields
    for product in data['products']:
        required_product_keys = ['product_name', 'total_quantity', 'total_revenue']
        for key in required_product_keys:
            assert key in product, f"Product missing key: {key}"
        assert isinstance(product['total_quantity'], int), "total_quantity should be integer"
        assert isinstance(product['total_revenue'], (int, float)), "total_revenue should be number"

def test_output_data_correct():
    """Verify data aggregation is correct."""
    # Read and process input data to verify calculations
    electronics_data = {}
    
    with open('/app/sales_data.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row['category'] == 'Electronics':
                product_name = row['product_name']
                quantity = int(row['quantity'])
                unit_price = float(row['unit_price'])
                revenue = quantity * unit_price
                
                if product_name not in electronics_data:
                    electronics_data[product_name] = {
                        'total_quantity': 0,
                        'total_revenue': 0.0
                    }
                
                electronics_data[product_name]['total_quantity'] += quantity
                electronics_data[product_name]['total_revenue'] += revenue
    
    # Read output
    with open('/app/electronics_summary.json', 'r') as f:
        output_data = json.load(f)
    
    # Check total_products count
    expected_product_count = len(electronics_data)
    assert output_data['total_products'] == expected_product_count, \
        f"Expected {expected_product_count} products, got {output_data['total_products']}"
    
    # Check each product's calculations
    for output_product in output_data['products']:
        product_name = output_product['product_name']
        assert product_name in electronics_data, f"Unexpected product: {product_name}"
        
        expected = electronics_data[product_name]
        # Round to 2 decimal places for comparison
        expected_revenue = Decimal(str(expected['total_revenue'])).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)
        actual_revenue = Decimal(str(output_product['total_revenue'])).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)
        
        assert output_product['total_quantity'] == expected['total_quantity'], \
            f"Quantity mismatch for {product_name}: expected {expected['total_quantity']}, got {output_product['total_quantity']}"
        
        assert actual_revenue == expected_revenue, \
            f"Revenue mismatch for {product_name}: expected {expected_revenue}, got {actual_revenue}"

def test_output_sorted():
    """Verify products are sorted by total_revenue descending."""
    with open('/app/electronics_summary.json', 'r') as f:
        data = json.load(f)
    
    revenues = [product['total_revenue'] for product in data['products']]
    
    # Check if sorted in descending order
    for i in range(len(revenues) - 1):
        assert revenues[i] >= revenues[i + 1], \
            f"Products not sorted by revenue descending: {revenues[i]} < {revenues[i + 1]}"