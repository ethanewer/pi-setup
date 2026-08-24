# Security Configuration Auditor

## Background
You are a security engineer tasked with auditing a configuration file for common security issues. A junior developer has created a configuration file for a web application, but it contains several security vulnerabilities and misconfigurations.

## Your Task

1. **Read the configuration file** located at `/app/config.yaml`
2. **Analyze the configuration** and identify the following security issues:
   - Hardcoded secrets or credentials
   - Insecure default values
   - Missing security headers or settings
   - Weak cryptographic parameters
   - Improper file permissions
3. **Generate a security report** with specific fixes
4. **Create a corrected configuration file**

## Requirements

### Input File Format
The `/app/config.yaml` file contains YAML configuration with the following structure (example):
```yaml
database:
  host: "localhost"
  username: "admin"
  password: "password123"
  port: 5432

security:
  session_timeout: 3600
  cookie_secure: false
  cors_origin: "*"

api:
  rate_limit: 1000
  debug_mode: true
```

### Analysis Steps

1. **Load and parse** the YAML configuration from `/app/config.yaml`
2. **Identify vulnerabilities** by checking for:
   - Weak passwords (common/default values)
   - Insecure flags set to `true` (like `debug_mode`)
   - Missing security headers (like `X-Frame-Options`)
   - Excessive permissions (like `cors_origin: "*"`)
   - Insecure defaults (like non-HTTPS cookies)
3. **Categorize each finding** as:
   - CRITICAL: Immediate security risk (e.g., hardcoded credentials)
   - HIGH: Significant security weakness (e.g., debug mode enabled)
   - MEDIUM: Security best practice violation (e.g., weak CORS settings)
   - LOW: Minor configuration issue

### Output Requirements

Create two output files:

1. **Security Report** (`/app/security_report.json`):
   ```json
   {
     "findings": [
       {
         "category": "CRITICAL|HIGH|MEDIUM|LOW",
         "location": "path.to.setting",
         "issue": "Description of the security issue",
         "recommendation": "Specific fix to apply"
       }
     ],
     "summary": {
       "critical_count": 0,
       "high_count": 0,
       "medium_count": 0,
       "low_count": 0,
       "total_findings": 0
     }
   }
   ```

2. **Corrected Configuration** (`/app/config_fixed.yaml`):
   - Apply all recommended fixes from the report
   - Maintain the original YAML structure and comments
   - Replace insecure values with secure alternatives
   - Add missing security settings with appropriate values

## Expected Outputs

- `/app/security_report.json`: JSON report with vulnerability findings
- `/app/config_fixed.yaml`: Corrected YAML configuration file

## Success Criteria

The tests will verify:
1. All security issues in the input configuration are identified and categorized correctly
2. The fixed configuration resolves all identified issues
3. The report contains accurate counts and properly formatted JSON
4. The fixed configuration maintains functional equivalence (non-security settings unchanged)

## Example

Given this insecure configuration:
```yaml
auth:
  jwt_secret: "secret"
  token_expiry: 999999
```

Your report should contain:
```json
{
  "findings": [
    {
      "category": "CRITICAL",
      "location": "auth.jwt_secret",
      "issue": "Hardcoded weak JWT secret",
      "recommendation": "Replace with strong randomly generated secret stored in environment variable"
    },
    {
      "category": "MEDIUM", 
      "location": "auth.token_expiry",
      "issue": "Excessively long token expiration",
      "recommendation": "Set to reasonable value (e.g., 3600 for 1 hour)"
    }
  ],
  "summary": {
    "critical_count": 1,
    "high_count": 0,
    "medium_count": 1,
    "low_count": 0,
    "total_findings": 2
  }
}
```

And the fixed configuration should have these issues resolved.