## Refactoring and Validation of Build Configuration

You are tasked with cleaning up and validating a Python project's build configuration. The project has a messy `requirements.txt` file with duplicate entries, inconsistent version specifiers, and mixed dependencies. Your job is to refactor this file into a clean, valid format and generate a summary report.

## Your Task

1. **Read the input file** located at `/app/requirements.txt` which contains package requirements in various formats
2. **Process the requirements** by:
   - Removing duplicate package entries (keeping the first occurrence)
   - Normalizing version specifiers to use `==` (exact version) format
   - Removing any blank lines or comment lines (starting with #)
   - Sorting the resulting packages alphabetically by package name
3. **Write the cleaned requirements** to `/app/clean_requirements.txt` with each package on a separate line
4. **Generate a summary report** at `/app/summary.json` containing:
   - `original_count`: total lines in the original file (including comments and blank lines)
   - `cleaned_count`: number of packages in the cleaned file
   - `duplicates_removed`: number of duplicate packages removed
   - `packages`: alphabetically sorted list of package names (without versions)

## Input File Format

The input file `/app/requirements.txt` contains requirements in various formats:
- `package==1.0.0` (exact version)
- `package>=1.0.0` (minimum version)
- `package<=2.0.0` (maximum version)
- `package~=1.0` (compatible release)
- `package` (no version specified)
- Comment lines starting with `#`
- Blank lines

## Expected Outputs

- `/app/clean_requirements.txt`: Cleaned requirements file with one package per line in `package==version` format
- `/app/summary.json`: JSON file with the structure described above

## Example

**Input (`/app/requirements.txt`):**
```
# Core dependencies
numpy==1.21.0
pandas>=1.3.0
requests

# Testing
pytest~=6.2.5
pandas  # duplicate
numpy==1.21.0

flask>=2.0.0
requests==2.26.0
```

**Expected Output (`/app/clean_requirements.txt`):**
```
flask==2.0.0
numpy==1.21.0
pandas==1.3.0
pytest==6.2.5
requests==2.26.0
```

**Expected Output (`/app/summary.json`):**
```json
{
  "original_count": 9,
  "cleaned_count": 5,
  "duplicates_removed": 2,
  "packages": ["flask", "numpy", "pandas", "pytest", "requests"]
}
```

## Notes

- When multiple version specifiers exist for the same package, use the exact version if present (`==`), otherwise use the first occurrence's version converted to `==` format
- If no version is specified, default to `==0.0.0` (e.g., `requests` becomes `requests==0.0.0`)
- Version normalization: `>=1.0.0` → `==1.0.0`, `<=2.0.0` → `==2.0.0`, `~=1.0` → `==1.0`
- The tests will verify file existence, JSON validity, and correct processing of the requirements