# Security Challenge: Secret Scanner & Validator

You are tasked with building a simple security scanner that detects and validates sensitive information in files. This task focuses on basic security practices like input validation, pattern matching, and safe file operations.

## Your Task

Create a Python script that:

1. **Scan files for secrets**: Search through all files in `/app/secrets/` directory for patterns that might indicate sensitive information
2. **Validate secret format**: Validate that found secrets match expected security standards
3. **Generate security report**: Create a summary report of findings

### Specific Requirements

#### 1. File Scanning
- Recursively search all files in `/app/secrets/` directory
- Look for patterns indicating potential secrets:
  - API keys: `"api_key":\s*"([^"]+)"`
  - Passwords: `"password":\s*"([^"]+)"`
  - Access tokens: `"access_token":\s*"([^"]+)"`
  - Database URLs: `"database_url":\s*"([^"]+)"`
- Extract the secret values (the part in quotes after the colon)

#### 2. Secret Validation
For each extracted secret, validate it meets security standards:
- **API keys**: Must be at least 32 characters long
- **Passwords**: Must be at least 12 characters long and contain at least one uppercase letter, one lowercase letter, one digit, and one special character
- **Access tokens**: Must be exactly 64 hexadecimal characters (0-9, a-f)
- **Database URLs**: Must start with `postgresql://`, `mysql://`, or `mongodb://`

#### 3. Output Generation
Create a JSON report at `/app/output/security_report.json` with this exact structure:
```json
{
  "total_files_scanned": 123,
  "total_secrets_found": 45,
  "valid_secrets_by_type": {
    "api_key": 5,
    "password": 3,
    "access_token": 8,
    "database_url": 2
  },
  "invalid_secrets_by_type": {
    "api_key": 2,
    "password": 7,
    "access_token": 1,
    "database_url": 0
  },
  "validation_errors": [
    "Password 'test123' is too short (must be at least 12 characters)",
    "Access token 'xyz123' is not 64 hex characters"
  ]
}
```

#### 4. Error Handling
- Skip files that cannot be read (log to validation_errors)
- Handle malformed JSON/patterns gracefully
- Continue scanning even if some files fail

## Expected Outputs
- **Main output**: `/app/output/security_report.json` - JSON report with scan results
- **Optional debug**: `/app/output/debug.log` - Can contain debug info (optional)

## Success Criteria
1. The script must find all secrets in the provided test files
2. Each secret must be correctly categorized and validated
3. The JSON report must match the exact structure shown above
4. Validation rules must be strictly applied
5. All files in `/app/secrets/` must be processed (successfully or with error logging)

## Hints
- Use `os.walk()` for recursive directory traversal
- Regular expressions will help with pattern matching
- Validate password complexity with multiple checks
- Remember that hex strings can be lowercase or uppercase
- Handle exceptions when reading files