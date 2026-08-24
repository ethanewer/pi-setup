import os
import csv
import re
from rdflib import Graph, Namespace
from rdflib.plugins.sparql import prepareQuery

def test_output_exists():
    """Verify output files were created."""
    assert os.path.exists('/app/query.sparql'), "query.sparql file not found"
    assert os.path.exists('/app/results.csv'), "results.csv file not found"

def test_sparql_syntax():
    """Verify SPARQL query has valid syntax."""
    with open('/app/query.sparql', 'r') as f:
        query_text = f.read()
    
    # Check for required components
    assert 'PREFIX ex:' in query_text, "Missing ex namespace prefix"
    assert 'SELECT' in query_text, "Missing SELECT clause"
    assert 'FILTER' in query_text, "Missing FILTER clause"
    assert ('CONTAINS' in query_text or 'regex' in query_text), "Missing string filter"
    assert 'OPTIONAL' in query_text, "Missing OPTIONAL for awards"
    assert 'ORDER BY' in query_text, "Missing ORDER BY clause"
    
    # Try to parse as SPARQL
    try:
        query = prepareQuery(query_text)
        assert query is not None, "Failed to parse SPARQL query"
    except Exception as e:
        assert False, f"SPARQL syntax error: {e}"

def test_csv_format():
    """Verify CSV has correct format and headers."""
    with open('/app/results.csv', 'r') as f:
        reader = csv.reader(f)
        rows = list(reader)
    
    assert len(rows) > 0, "CSV file is empty"
    
    # Check headers
    assert rows[0] == ['book_title', 'author_name', 'publication_year', 'award_name'], \
        f"Incorrect headers. Expected {['book_title', 'author_name', 'publication_year', 'award_name']}, got {rows[0]}"
    
    # Check all rows have 4 columns
    for i, row in enumerate(rows[1:], start=2):
        assert len(row) == 4, f"Row {i} has {len(row)} columns, expected 4: {row}"
    
    # Check year values are integers
    for i, row in enumerate(rows[1:], start=2):
        try:
            int(row[2])
        except ValueError:
            assert False, f"Row {i} has non-integer year: {row[2]}"

def test_query_results():
    """Verify query returns correct results."""
    # Load the RDF data
    g = Graph()
    g.parse('/app/bookstore.ttl', format='turtle')
    
    # Load and execute the query
    with open('/app/query.sparql', 'r') as f:
        query_text = f.read()
    
    try:
        query = prepareQuery(query_text)
        results = g.query(query)
    except Exception as e:
        assert False, f"Failed to execute query: {e}"
    
    # Expected books matching criteria:
    # 1. Leviathan Wakes (2011, Science Fiction, Hugo Award, author doesn't contain Martin)
    # 2. Ancillary Justice (2013, Science Fiction, Hugo Award)
    # 3. The Martian (2014, Science Fiction, no award, author doesn't contain Martin)
    # 4. The Three-Body Problem (2014, Science Fiction, Hugo Award)
    
    results_list = []
    for row in results:
        # Convert RDF literals to strings
        book = str(row[0]) if row[0] else ""
        author = str(row[1]) if row[1] else ""
        year = str(row[2]) if row[2] else ""
        award = str(row[3]) if row[3] else "None"
        
        # Normalize award string
        if award.lower() == "none" or award == "":
            award = "None"
        
        results_list.append([book, author, year, award])
    
    # Sort by year desc, then title for consistent comparison
    results_list.sort(key=lambda x: (-int(x[2]), x[0]))
    
    # Load CSV results for comparison
    with open('/app/results.csv', 'r') as f:
        reader = csv.reader(f)
        csv_rows = list(reader)[1:]  # Skip header
    
    # Sort CSV rows for comparison
    csv_rows.sort(key=lambda x: (-int(x[2]), x[0]))
    
    # Check we have 4 results
    assert len(results_list) == 4, f"Expected 4 results, got {len(results_list)}"
    assert len(csv_rows) == 4, f"Expected 4 rows in CSV, got {len(csv_rows)}"
    
    # Verify each result
    expected_titles = {"The Three-Body Problem", "The Martian", "Ancillary Justice", "Leviathan Wakes"}
    found_titles = {row[0] for row in results_list}
    
    assert found_titles == expected_titles, \
        f"Expected titles {expected_titles}, got {found_titles}"
    
    # Check CSV matches query results
    for i, (query_row, csv_row) in enumerate(zip(results_list, csv_rows)):
        assert query_row == csv_row, \
            f"Row {i+1} mismatch: Query={query_row}, CSV={csv_row}"

def test_sorting():
    """Verify results are sorted correctly."""
    with open('/app/results.csv', 'r') as f:
        reader = csv.reader(f)
        rows = list(reader)[1:]  # Skip header
    
    # Check sorting: year descending, then title ascending
    years = [int(row[2]) for row in rows]
    assert years == sorted(years, reverse=True), "Not sorted by year descending"
    
    # For books with same year, check title order
    for i in range(len(rows)-1):
        if rows[i][2] == rows[i+1][2]:  # Same year
            assert rows[i][0] <= rows[i+1][0], \
                f"Titles not sorted alphabetically for year {rows[i][2]}: {rows[i][0]} > {rows[i+1][0]}"