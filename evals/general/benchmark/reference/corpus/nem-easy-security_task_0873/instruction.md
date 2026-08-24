## Security Audit: Password Policy Validator

You are tasked with performing a security audit on a legacy application's password storage. The application stores user passwords in a directory structure with base64-encoded files, but the security team suspects weak passwords may have been accepted due to a bug in the validation logic.

## Your Task

1. **Navigate and Read Files**: Recursively traverse the directory `/app/password_data/` to find all files with the `.pw` extension. Each file contains one base64-encoded password per line.

2. **Decode and Validate**: For each password in these files:
   - Decode the base64 string to plain text
   - Apply the organization's password policy:
     - Minimum 12 characters
     - Must contain at least one uppercase letter (A-Z)
     - Must contain at least one lowercase letter (a-z)  
     - Must contain at least one digit (0-9)
     - Must contain at least one special character from: !@#$%^&*()
     - Must NOT contain the username (filename without `.pw`) anywhere in the password
   - Usernames are the filenames without the `.pw` extension (e.g., `alice.pw` → username is `alice`)

3. **Generate Security Report**: Create a JSON report at `/app/output/security_report.json` with the following structure:
   ```json
   {
     "total_passwords_checked": 42,
     "weak_passwords_count": 7,
     "weak_passwords": [
       {
         "file": "alice.pw",
         "line": 3,
         "password": "password123",
         "violations": ["too_short", "no_special_char", "contains_username"]
       }
     ],
     "strong_passwords_count": 35
   }
   ```

4. **Archive Weak Passwords**: Create a secure archive of all weak passwords at `/app/output/weak_passwords.txt` with each weak password on a new line (plain text, not base64). Sort this file alphabetically.

## Expected Outputs

- **Security Report**: `/app/output/security_report.json` - JSON file with audit results
- **Weak Passwords Archive**: `/app/output/weak_passwords.txt` - Sorted list of weak passwords (one per line)

## File Structure Example

```
/app/password_data/
├── users/
│   ├── alice.pw
│   └── bob.pw
└── admins/
    └── admin.pw
```

**Note**: Tests will verify:
1. Your report matches the exact structure and contains correct counts
2. The weak passwords file contains exactly the weak passwords found (sorted)
3. All base64 decoding is performed correctly
4. Password policy is applied consistently