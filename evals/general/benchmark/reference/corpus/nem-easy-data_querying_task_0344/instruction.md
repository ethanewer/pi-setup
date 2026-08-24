# SPARQL Bookstore Query Challenge

You are working with a bookstore's RDF dataset in Turtle format. The dataset contains information about books, authors, and their relationships.

## Your Task

1. **Write a SPARQL query** that finds all science fiction books published after 2010 by authors whose names contain "Martin" OR books that have won the "Hugo Award". The query should return:
   - Book title
   - Author name  
   - Publication year
   - Award name (if any, otherwise show "None")

2. **Save the query** to `/app/query.sparql` using proper SPARQL syntax with namespace prefixes.

3. **Run the query** against the provided dataset and save results to `/app/results.csv` in CSV format with headers: `book_title,author_name,publication_year,award_name`

## Dataset Information

The RDF data is stored at `/app/bookstore.ttl` with the following structure:

- Books have type `ex:Book` with properties: `ex:title`, `ex:publicationYear`, `ex:genre`
- Authors have type `ex:Author` with property `ex:name`
- Books are linked to authors via `ex:writtenBy`
- Awards are linked to books via `ex:wonAward`
- Genres include: "Science Fiction", "Fantasy", "Mystery"
- Awards include: "Hugo Award", "Nebula Award", "World Fantasy Award"

## Namespace Prefixes
```
PREFIX ex: <http://example.org/books#>
PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
```

## Requirements

- Use appropriate SPARQL syntax with FILTER, OPTIONAL, and logical operators
- Handle NULL award values by returning "None" string
- Sort results by publication year (descending), then book title
- Ensure CSV output has exactly the 4 specified columns with proper headers
- The CSV must not contain duplicate rows

## Expected Outputs
- `/app/query.sparql`: Valid SPARQL query file with namespace declarations
- `/app/results.csv`: CSV file with 4 columns and header row, containing all matching books

## Testing Criteria
Tests will verify:
1. Both output files exist at the specified paths
2. The SPARQL query is syntactically valid
3. The CSV contains the expected number of rows (4 books match the criteria)
4. All rows have correct values in the expected columns
5. Results are properly sorted by year (desc) then title
6. Missing awards are shown as "None"