## Book Catalog Data Transformation

You are assisting a library system that needs to convert their book catalog data from CSV format to a structured JSON format for their new web application.

## Your Task

Process the book catalog data from `/app/books.csv` and create two output files:

1. **Main JSON catalog** (`/app/books.json`): A JSON array containing all books, with specific formatting requirements:
   - Each book should be an object with these exact keys (renamed from CSV columns):
     - `id` (from "BookID")
     - `title` (from "Title")
     - `author` (from "Author")
     - `genre` (from "Category")
     - `publication_year` (from "Year")
   - Books must be sorted alphabetically by `author` (A-Z), then by `title` (A-Z)
   - The entire array must be pretty-printed with 2-space indentation

2. **Genre summary** (`/app/genre_summary.json`): A JSON object counting books by genre:
   - Keys are genre names (from "Category" column)
   - Values are the count of books in that genre
   - Genres must be sorted alphabetically (A-Z)
   - Format with 2-space indentation

## Input File Format

The CSV file at `/app/books.csv` has these columns:
- BookID (string)
- Title (string)
- Author (string)
- Category (string)
- Year (integer)

Note: Some rows may have missing values in the Category column (empty string). These books should still be included in the main catalog but excluded from genre counts.

## Example Transformation

If the CSV contains:
```
BookID,Title,Author,Category,Year
B001,Python Basics,John Smith,Programming,2020
B002,Data Science,Jane Doe,,2021
B003,Advanced Python,John Smith,Programming,2022
```

The `/app/books.json` should contain:
```json
[
  {
    "id": "B002",
    "title": "Data Science",
    "author": "Jane Doe",
    "genre": "",
    "publication_year": 2021
  },
  {
    "id": "B001",
    "title": "Python Basics",
    "author": "John Smith",
    "genre": "Programming",
    "publication_year": 2020
  },
  {
    "id": "B003",
    "title": "Advanced Python",
    "author": "John Smith",
    "genre": "Programming",
    "publication_year": 2022
  }
]
```

And `/app/genre_summary.json` should contain:
```json
{
  "Programming": 2
}
```

## Expected Outputs
- `/app/books.json` - Main catalog in JSON array format
- `/app/genre_summary.json` - Genre counts in JSON object format

Both files must be valid JSON and parseable by `json.load()`.