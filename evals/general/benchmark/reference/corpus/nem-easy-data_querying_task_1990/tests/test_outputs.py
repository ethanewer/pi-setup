import os
import json
import pytest
from rdflib import Graph, Namespace
from rdflib.plugins.sparql import prepareQuery

def test_output_exists():
    """Verify output file was created."""
    assert os.path.exists('/app/query_results.json'), "Output file not found"

def test_output_correct():
    """Verify output content is correct."""
    # Load the output
    with open('/app/query_results.json', 'r') as f:
        output = json.load(f)
    
    # Check structure
    assert 'query' in output, "Missing 'query' field"
    assert 'results' in output, "Missing 'results' field"
    assert isinstance(output['results'], list), "'results' should be a list"
    
    # Check query is a non-empty string
    assert isinstance(output['query'], str), "'query' should be a string"
    assert len(output['query'].strip()) > 0, "Query string is empty"
    
    # Load the dataset
    g = Graph()
    g.parse('/app/books.ttl', format='turtle')
    
    # Execute the query from the output
    try:
        query = prepareQuery(output['query'])
        actual_results = list(g.query(query))
    except Exception as e:
        pytest.fail(f"Query execution failed: {e}")
    
    # Expected results (from manual inspection of the dataset)
    expected_data = [
        {"title": "The Art of Programming", "year": 2020, "language": "en"},
        {"title": "Data Structures Explained", "year": 2022, "language": "en"}
    ]
    
    # Check number of results
    assert len(output['results']) == len(expected_data), f"Expected {len(expected_data)} results, got {len(output['results'])}"
    
    # Check each result matches expected
    for i, (expected, actual_dict) in enumerate(zip(expected_data, output['results'])):
        assert actual_dict['title'] == expected['title'], f"Result {i}: title mismatch"
        assert actual_dict['year'] == expected['year'], f"Result {i}: year mismatch"
        assert actual_dict['language'] == expected['language'], f"Result {i}: language mismatch"
    
    # Verify sorting by year
    years = [r['year'] for r in output['results']]
    assert years == sorted(years), "Results should be sorted by year ascending"