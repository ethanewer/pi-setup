import os
import json
import csv

def test_summary_file_exists():
    """Verify summary.txt was created."""
    assert os.path.exists('/app/summary.txt'), "summary.txt not found"

def test_category_file_exists():
    """Verify category_totals.csv was created."""
    assert os.path.exists('/app/category_totals.csv'), "category_totals.csv not found"

def test_summary_content():
    """Verify summary.txt contains correct data."""
    with open('/app/summary.txt', 'r') as f:
        content = f.read()
    lines = [line.strip() for line in content.strip().split('\n')]
    
    # Read input data to calculate expected values
    with open('/app/transactions.json', 'r') as f:
        data = json.load(f)
    
    # Calculate expected values
    valid_transactions = [t for t in data if isinstance(t.get('amount'), (int, float))]
    total_count = len(valid_transactions)
    total_amount = sum(t['amount'] for t in valid_transactions)
    avg_amount = total_amount / total_count if total_count > 0 else 0
    count_over_100 = sum(1 for t in valid_transactions if t['amount'] > 100.00)
    
    expected_lines = [
        f"Total Transactions: {total_count}",
        f"Total Amount: ${total_amount:.2f}",
        f"Average Transaction: ${avg_amount:.2f}",
        f"Transactions > $100: {count_over_100}"
    ]
    
    assert len(lines) == 4, f"Expected 4 lines, got {len(lines)}"
    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch:\nExpected: {expected}\nGot: {actual}"

def test_category_csv_format():
    """Verify category_totals.csv has correct format and content."""
    with open('/app/category_totals.csv', 'r') as f:
        reader = csv.reader(f)
        rows = list(reader)
    
    # Check headers
    assert rows[0] == ['Category', 'Total_Amount', 'Transaction_Count'], \
        f"Wrong headers. Expected ['Category', 'Total_Amount', 'Transaction_Count'], got {rows[0]}"
    
    # Check data rows are sorted alphabetically
    categories = [row[0] for row in rows[1:]]
    assert categories == sorted(categories), f"Categories not sorted alphabetically: {categories}"
    
    # Verify calculations match input data
    with open('/app/transactions.json', 'r') as f:
        data = json.load(f)
    
    # Group and calculate category totals
    category_data = {}
    for t in data:
        if isinstance(t.get('amount'), (int, float)):
            category = t.get('category', '').strip() or 'Uncategorized'
            amount = float(t['amount'])
            
            if category not in category_data:
                category_data[category] = {'total': 0.0, 'count': 0}
            category_data[category]['total'] += amount
            category_data[category]['count'] += 1
    
    # Sort categories alphabetically
    sorted_categories = sorted(category_data.keys())
    
    # Check each row matches expected values
    for i, category in enumerate(sorted_categories):
        row_index = i + 1
        expected_total = f"{category_data[category]['total']:.2f}"
        expected_count = str(category_data[category]['count'])
        
        assert rows[row_index][0] == category, \
            f"Row {row_index}: Expected category '{category}', got '{rows[row_index][0]}'"
        
        # Check total amount (allowing for floating point rounding)
        actual_total = float(rows[row_index][1])
        expected_total_float = float(expected_total)
        assert abs(actual_total - expected_total_float) < 0.01, \
            f"Row {row_index}: Expected total {expected_total}, got {rows[row_index][1]}"
        
        assert rows[row_index][2] == expected_count, \
            f"Row {row_index}: Expected count {expected_count}, got {rows[row_index][2]}"