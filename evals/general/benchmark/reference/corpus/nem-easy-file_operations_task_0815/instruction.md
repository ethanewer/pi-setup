## File Operation Validator

You are tasked with creating a simple file operation validator that reads a configuration file and performs basic file system validation.

## Your Task

Create a Python script that:

1. **Read configuration** from `/app/config.json` which contains:
   - A list of file paths that should exist
   - A list of directory paths that should exist
   - A list of file extensions that should be present

2. **Validate file system state**:
   - Check if each specified file exists
   - Check if each specified directory exists  
   - Count how many files in the working directory have each specified extension

3. **Generate a summary report** at `/app/validation_report.txt` with:
   - A section "FILES:" listing each file path and its status (EXISTS or MISSING)
   - A section "DIRECTORIES:" listing each directory path and its status (EXISTS or MISSING)
   - A section "EXTENSIONS:" listing each extension and the count of files with that extension
   - Each section separated by a blank line
   - Each item in the sections formatted as: `[STATUS] path` or `[COUNT] .ext`

4. **Handle edge cases**:
   - If a file path doesn't exist, still list it as MISSING
   - If a directory doesn't exist, still list it as MISSING  
   - Count files with extensions case-insensitively (.txt and .TXT should both count)
   - Only count files, not directories, when counting extensions

## Expected Outputs

- A file at `/app/validation_report.txt` containing the validation results
- The output must follow the exact format specified above

## Example

Given this `/app/config.json`:
```json
{
  "files": ["/app/data.txt", "/app/notes.md", "/app/missing.txt"],
  "directories": ["/app/docs", "/app/images", "/app/backup"],
  "extensions": [".txt", ".md", ".py"]
}
```

And assuming:
- `/app/data.txt` exists
- `/app/notes.md` exists  
- `/app/missing.txt` does NOT exist
- `/app/docs` exists
- `/app/images` exists
- `/app/backup` does NOT exist
- There are 2 `.txt` files, 1 `.md` file, and 0 `.py` files in `/app`

The output `/app/validation_report.txt` should be:
```
FILES:
[EXISTS] /app/data.txt
[EXISTS] /app/notes.md
[MISSING] /app/missing.txt

DIRECTORIES:
[EXISTS] /app/docs
[EXISTS] /app/images
[MISSING] /app/backup

EXTENSIONS:
[2] .txt
[1] .md
[0] .py
```

**Note**: The tests will check that your output file follows this exact format, including spacing and ordering.