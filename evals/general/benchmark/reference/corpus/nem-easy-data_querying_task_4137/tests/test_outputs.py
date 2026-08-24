import os
import csv
from rdflib import Graph, Namespace
import tempfile

def test_output_files_exist():
    """Verify both required output files were created."""
    assert os.path.exists('/app/query.sparql'), "SPARQL query file missing"
    assert os.path.exists('/app/results.csv'), "Results CSV file missing"
    
def test_sparql_query_syntax():
    """Verify the SPARQL query is valid syntax."""
    with open('/app/query.sparql', 'r') as f:
        query = f.read()
    
    # Basic syntax checks
    assert "SELECT" in query, "Query must be a SELECT query"
    assert "?title" in query, "Query must select ?title"
    assert "?authorName" in query, "Query must select ?authorName"
    assert "?year" in query, "Query must select ?year"
    assert "?publisher" in query, "Query must select ?publisher"
    assert "Science Fiction" in query, "Query must filter for Science Fiction genre"
    
def test_query_execution():
    """Execute the SPARQL query and verify results."""
    # Load test data
    g = Graph()
    g.parse('/app/books.ttl', format='turtle')
    
    # Load and execute the user's query
    with open('/app/query.sparql', 'r') as f:
        query = f.read()
    
    results = list(g.query(query))
    
    # Should have exactly 3 results
    assert len(results) == 3, f"Expected 3 results, got {len(results)}"
    
    # Check each result has 4 values
    for row in results:
        assert len(row) == 4, f"Each result should have 4 values, got {len(row)}"
        
    # Verify ordering (by year, then title)
    years = [int(row[2]) for row in results]
    assert years == sorted(years), "Results not sorted by year"
    
    # For books with same year, check title order
    for i in range(len(results)-1):
        if results[i][2] == results[i+1][2]:  # Same year
            assert str(results[i][0]) <= str(results[i+1][0]), \
                f"Books with same year not sorted by title: {results[i][0]} > {results[i+1][0]}"
    
def test_csv_format():
    """Verify CSV file format and content."""
    with open('/app/results.csv', 'r') as f:
        reader = csv.reader(f)
        rows = list(reader)
    
    # Check headers
    assert rows[0] == ['title', 'author', 'year', 'publisher'], \
        f"Incorrect CSV headers: {rows[0]}"
    
    # Check data rows (should have 3 rows + header)
    assert len(rows) == 4, f"Expected 4 rows (header + 3 data), got {len(rows)}"
    
    # Verify data values
    data_rows = rows[1:]
    
    # Check each row has 4 columns
    for i, row in enumerate(data_rows):
        assert len(row) == 4, f"Row {i+1} has {len(row)} columns, expected 4"
    
    # Check specific expected books (based on test data)
    titles = [row[0] for row in data_rows]
    expected_titles = ["Foundation", "Dune", "Neuromancer"]
    
    for title in expected_titles:
        assert title in titles, f"Expected book '{title}' not found in results"
    
    # Check years are >= 1950
    years = [int(row[2]) for row in data_rows]
    for year in years:
        assert year >= 1950, f"Book published before 1950: {year}"
        
    # Check ordering
    assert years == sorted(years), "CSV results not sorted by year"
    
def test_complete_solution():
    """Run all tests to verify complete solution."""
    test_output_files_exist()
    test_sparql_query_syntax()
    test_query_execution()
    test_csv_format()