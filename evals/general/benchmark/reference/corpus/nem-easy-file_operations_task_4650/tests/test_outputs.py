import os
import json
import pytest

def test_output_exists():
    """Verify output file was created."""
    assert os.path.exists('/app/summary.json')

def test_output_structure():
    """Verify output has correct structure and data types."""
    with open('/app/summary.json', 'r') as f:
        data = json.load(f)
    
    # Check overall structure
    assert 'overall' in data
    assert 'categories' in data
    
    # Check overall fields
    overall = data['overall']
    assert 'total_revenue' in overall
    assert 'average_transaction' in overall
    assert 'valid_transactions' in overall
    assert 'invalid_lines' in overall
    
    # Check data types
    assert isinstance(overall['total_revenue'], (int, float))
    assert isinstance(overall['average_transaction'], (int, float))
    assert isinstance(overall['valid_transactions'], int)
    assert isinstance(overall['invalid_lines'], int)
    
    # Check categories structure
    categories = data['categories']
    assert isinstance(categories, dict)
    
    for cat_name, cat_data in categories.items():
        assert 'items_sold' in cat_data
        assert 'revenue' in cat_data
        assert 'avg_price_per_item' in cat_data
        assert isinstance(cat_data['items_sold'], int)
        assert isinstance(cat_data['revenue'], (int, float))
        assert isinstance(cat_data['avg_price_per_item'], (int, float))

def test_output_correct():
    """Verify calculated values are correct."""
    # Read and process input file
    valid_transactions = []
    categories_data = {}
    invalid_lines = 0
    
    with open('/app/sales.txt', 'r') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
                
            parts = line.split(',')
            if len(parts) != 4:
                invalid_lines += 1
                continue
            
            item_name, category, price_str, qty_str = parts
            
            try:
                price = float(price_str)
                quantity = int(qty_str)
            except ValueError:
                invalid_lines += 1
                continue
            
            valid_transactions.append({
                'category': category,
                'price': price,
                'quantity': quantity,
                'revenue': price * quantity
            })
    
    # Calculate expected values
    total_revenue = sum(t['revenue'] for t in valid_transactions)
    avg_transaction = total_revenue / len(valid_transactions) if valid_transactions else 0
    
    # Calculate category data
    expected_categories = {}
    for t in valid_transactions:
        cat = t['category']
        if cat not in expected_categories:
            expected_categories[cat] = {
                'items_sold': 0,
                'revenue': 0,
                'transactions': []
            }
        expected_categories[cat]['items_sold'] += t['quantity']
        expected_categories[cat]['revenue'] += t['revenue']
        expected_categories[cat]['transactions'].append(t)
    
    # Read output file
    with open('/app/summary.json', 'r') as f:
        output_data = json.load(f)
    
    # Compare with expected values (allow for floating point rounding)
    tolerance = 0.01
    
    # Check overall stats
    assert abs(output_data['overall']['total_revenue'] - total_revenue) < tolerance
    assert abs(output_data['overall']['average_transaction'] - avg_transaction) < tolerance
    assert output_data['overall']['valid_transactions'] == len(valid_transactions)
    assert output_data['overall']['invalid_lines'] == invalid_lines
    
    # Check category stats
    for cat, expected in expected_categories.items():
        output_cat = output_data['categories'].get(cat)
        assert output_cat is not None, f"Category '{cat}' missing in output"
        
        expected_avg = expected['revenue'] / expected['items_sold'] if expected['items_sold'] > 0 else 0
        
        assert output_cat['items_sold'] == expected['items_sold']
        assert abs(output_cat['revenue'] - expected['revenue']) < tolerance
        assert abs(output_cat['avg_price_per_item'] - expected_avg) < tolerance
    
    # Check no extra categories in output
    assert set(output_data['categories'].keys()) == set(expected_categories.keys())