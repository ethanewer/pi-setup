import os
import json
import pandas as pd
import pytest

def test_output_files_exist():
    """Verify both output files were created."""
    assert os.path.exists('/app/books.json'), "books.json not found"
    assert os.path.exists('/app/genre_summary.json'), "genre_summary.json not found"

def test_books_json_valid():
    """Verify books.json is valid JSON and has correct structure."""
    with open('/app/books.json', 'r') as f:
        books = json.load(f)
    
    # Check it's a list
    assert isinstance(books, list), "books.json should be a JSON array"
    
    # Check each book has required fields
    required_keys = {'id', 'title', 'author', 'genre', 'publication_year'}
    for book in books:
        assert isinstance(book, dict), "Each book should be an object"
        assert set(book.keys()) == required_keys, f"Book missing required keys: {book}"
        assert isinstance(book['id'], str), "id should be string"
        assert isinstance(book['title'], str), "title should be string"
        assert isinstance(book['author'], str), "author should be string"
        assert isinstance(book['genre'], str), "genre should be string"
        assert isinstance(book['publication_year'], int), "publication_year should be integer"

def test_books_sorted_correctly():
    """Verify books are sorted by author then title."""
    with open('/app/books.json', 'r') as f:
        books = json.load(f)
    
    # Check sorting
    for i in range(len(books) - 1):
        current = books[i]
        next_book = books[i + 1]
        
        # Compare author then title
        if current['author'] == next_book['author']:
            assert current['title'] <= next_book['title'], \
                f"Books by same author not sorted by title: {current['title']} > {next_book['title']}"
        else:
            assert current['author'] <= next_book['author'], \
                f"Authors not sorted: {current['author']} > {next_book['author']}"

def test_genre_summary_valid():
    """Verify genre_summary.json is valid and has correct structure."""
    with open('/app/genre_summary.json', 'r') as f:
        summary = json.load(f)
    
    # Check it's an object/dict
    assert isinstance(summary, dict), "genre_summary.json should be a JSON object"
    
    # Check keys are strings and values are integers
    for genre, count in summary.items():
        assert isinstance(genre, str), "Genre key should be string"
        assert isinstance(count, int), "Count should be integer"
        assert count > 0, f"Count for {genre} should be positive"

def test_genre_summary_sorted():
    """Verify genres are sorted alphabetically."""
    with open('/app/genre_summary.json', 'r') as f:
        summary = json.load(f)
    
    genres = list(summary.keys())
    assert genres == sorted(genres), "Genres should be sorted alphabetically"

def test_data_correctness():
    """Verify the transformation matches the CSV data."""
    # Read original CSV
    df = pd.read_csv('/app/books.csv')
    
    # Read output files
    with open('/app/books.json', 'r') as f:
        books = json.load(f)
    
    with open('/app/genre_summary.json', 'r') as f:
        summary = json.load(f)
    
    # Test 1: All CSV rows are in books.json
    assert len(books) == len(df), f"Expected {len(df)} books, got {len(books)}"
    
    # Test 2: Check a sample of transformations
    csv_by_id = {row['BookID']: row for _, row in df.iterrows()}
    for book in books:
        csv_row = csv_by_id[book['id']]
        assert book['title'] == csv_row['Title'], f"Title mismatch for {book['id']}"
        assert book['author'] == csv_row['Author'], f"Author mismatch for {book['id']}"
        assert book['genre'] == (csv_row['Category'] if pd.notna(csv_row['Category']) else ""), \
            f"Genre mismatch for {book['id']}"
        assert book['publication_year'] == int(csv_row['Year']), f"Year mismatch for {book['id']}"
    
    # Test 3: Genre counts are correct
    non_empty_genres = df[df['Category'].notna()]['Category'].unique()
    expected_genres = sorted(non_empty_genres)
    actual_genres = sorted(summary.keys())
    
    assert actual_genres == expected_genres, f"Expected genres {expected_genres}, got {actual_genres}"
    
    for genre in actual_genres:
        expected_count = len(df[df['Category'] == genre])
        assert summary[genre] == expected_count, \
            f"Count for {genre} should be {expected_count}, got {summary[genre]}"