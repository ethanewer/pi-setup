# SPARQL Query for Book Catalog

You have been given an RDF dataset in Turtle format describing books in a library catalog. Your task is to write and execute a SPARQL query to extract specific information from this dataset.

## Dataset Description

The dataset (`/app/books.ttl`) contains information about books, authors, and publications. It uses the following namespaces:

- `ex:` - Example namespace for our data (http://example.org/)
- `rdf:` - RDF vocabulary (http://www.w3.org/1999/02/22-rdf-syntax-ns#)
- `rdfs:` - RDFS vocabulary (http://www.w3.org/2000/01/rdf-schema#)
- `dc:` - Dublin Core terms (http://purl.org/dc/elements/1.1/)

Each book has:
- A type declaration (`rdf:type ex:Book`)
- A title (`dc:title`)
- An author (`dc:creator`)
- A publication year (`ex:publicationYear`)
- A language (`ex:language`)

Authors are also described as resources with their own properties.

## Your Task

Write a SPARQL query that finds all books written by "Jane Smith" that are published in English (language "en"). For each matching book, retrieve:

1. The book's title
2. The publication year
3. The language

Then execute this query against the provided dataset and save the results to `/app/query_results.json` in the following JSON format:

```json
{
  "query": "Your SPARQL query here",
  "results": [
    {
      "title": "Book Title 1",
      "year": 2020,
      "language": "en"
    },
    {
      "title": "Book Title 2", 
      "year": 2021,
      "language": "en"
    }
  ]
}
```

## Requirements

1. **Write the SPARQL query**:
   - Use appropriate namespace prefixes
   - Include all necessary graph patterns to match books by Jane Smith in English
   - Use FILTER conditions for author name and language
   - SELECT the required variables (title, year, language)

2. **Execute the query** against `/app/books.ttl` using any method you prefer (e.g., Python with rdflib)

3. **Format the output** as specified above:
   - The `query` field should contain your complete SPARQL query as a string
   - The `results` field should be an array of objects, each with `title`, `year`, and `language` keys
   - `year` values should be integers
   - Results should be sorted by publication year (ascending)

## Expected Outputs

- `/app/query_results.json`: JSON file containing the query and results as specified

## Verification

The tests will:
1. Check that `/app/query_results.json` exists and is valid JSON
2. Verify the SPARQL query syntax is correct
3. Validate that results contain exactly the books by Jane Smith in English
4. Confirm the output format matches the specification