# test_initial_state.py

import os
import json
import pytest

def test_customers_csv_exists_and_content():
    path = '/home/user/customers.csv'
    assert os.path.isfile(path), f"File missing: {path}"
    with open(path, 'r') as f:
        content = f.read()
    assert "customer_id,name" in content, f"Incorrect headers in {path}"
    assert "1,Alice" in content, f"Missing data in {path}"
    assert "2,Bob" in content, f"Missing data in {path}"
    assert "3,Charlie" in content, f"Missing data in {path}"

def test_orders_csv_exists_and_content():
    path = '/home/user/orders.csv'
    assert os.path.isfile(path), f"File missing: {path}"
    with open(path, 'r') as f:
        content = f.read()
    assert "order_id,customer_id,date" in content, f"Incorrect headers in {path}"
    assert "101,1,2023-01-01" in content, f"Missing data in {path}"

def test_items_csv_exists_and_content():
    path = '/home/user/items.csv'
    assert os.path.isfile(path), f"File missing: {path}"
    with open(path, 'r') as f:
        content = f.read()
    assert "item_id,order_id,price" in content, f"Incorrect headers in {path}"
    assert "1001,101,15.50" in content, f"Missing data in {path}"
    assert "1005,103,50.00" in content, f"Missing data in {path}"

def test_schema_json_exists_and_content():
    path = '/home/user/schema.json'
    assert os.path.isfile(path), f"File missing: {path}"
    with open(path, 'r') as f:
        try:
            schema = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Invalid JSON in {path}")

    assert schema.get("type") == "array", f"Incorrect schema type in {path}"
    items = schema.get("items", {})
    assert items.get("type") == "object", f"Incorrect items type in {path}"
    assert "customer_name" in items.get("properties", {}), f"Missing customer_name in schema properties"
    assert "total_spent" in items.get("properties", {}), f"Missing total_spent in schema properties"

def test_process_sales_script_exists_and_content():
    path = '/home/user/process_sales.py'
    assert os.path.isfile(path), f"File missing: {path}"
    with open(path, 'r') as f:
        content = f.read()

    # Check for the buggy query
    assert "FROM customers c, orders o, items i" in content, f"Missing buggy query FROM clause in {path}"
    assert "WHERE c.customer_id = o.customer_id" in content, f"Missing buggy query WHERE clause in {path}"
    assert "pd.read_sql_query" in content, f"Missing pandas read_sql_query in {path}"