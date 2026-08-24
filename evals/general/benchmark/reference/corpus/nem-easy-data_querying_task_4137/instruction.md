## Book Catalog SPARQL Query Task

You are working with a small book catalog stored as RDF/Turtle data. Your task is to write a SPARQL query to extract specific information from this dataset.

## Your Task

1. **Examine the RDF Data**: Read the book catalog data from `/app/books.ttl`. This file contains information about books, authors, and genres in Turtle format.

2. **Write a SPARQL Query**: Create a SPARQL query that finds all books in the "Science Fiction" genre and returns:
   - The book title (variable: `?title`)
   - The author's name (variable: `?authorName`)
   - The publication year (variable: `?year`)
   - The publisher name (variable: `?publisher`)

3. **Apply Filters**: Your query must:
   - Filter for books where the genre is exactly "Science Fiction" (case-sensitive)
   - Exclude books published before 1950
   - Include only books that have all four pieces of information (title, author, year, publisher)

4. **Sort Results**: Order the results by publication year (oldest first), then by book title (alphabetical).

5. **Save the Query**: Save your SPARQL query to `/app/query.sparql`

6. **Run the Query and Save Results**: Execute your query against the data and save the results to `/app/results.csv` in CSV format with the following specifications:
   - CSV headers: `title,author,year,publisher`
   - One book per row
   - Strings should be quoted if they contain commas
   - No extra whitespace around values

## Expected Outputs

- `/app/query.sparql`: A valid SPARQL query file
- `/app/results.csv`: CSV file with the query results

## Data Structure

The RDF data uses these predicates:
- `:hasTitle` - book title (string)
- `:hasAuthor` - links to author resource
- `:hasName` - author name (string)  
- `:hasGenre` - book genre (string)
- `:publishedIn` - publication year (integer)
- `:publishedBy` - publisher name (string)

Namespace prefixes are defined in the data file. Your query should use the same prefixes.

## Verification Criteria

The tests will:
1. Check that both output files exist
2. Validate that your SPARQL query is syntactically correct
3. Execute your query against the test data
4. Verify the CSV contains exactly 3 books matching all criteria
5. Check that results are properly sorted (by year, then title)
6. Validate CSV format (correct headers, proper quoting, no extra columns)

## Notes

- Use `rdflib` library to parse and query the RDF data
- The data file contains exactly 8 books total, but only 3 meet all criteria
- Books may have missing information (your query should filter these out)
- All required namespace prefixes are defined in `/app/books.ttl`