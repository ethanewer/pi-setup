# Security Audit: Command Injection Vulnerability Analysis and Fix

You are a security engineer performing a code audit on a simple web-based system monitor. The application is vulnerable to command injection attacks due to improper input handling in its ping functionality.

## Your Task

1. **Analyze the vulnerable application** at `/app/vulnerable_monitor.py`
   - Identify the command injection vulnerability
   - Document the security flaw in `/app/security_report.txt`

2. **Implement a secure version** of the application
   - Create `/app/fixed_monitor.py` with proper input validation
   - Use safe subprocess execution without shell=True
   - Validate and sanitize all user inputs
   - Implement proper error handling

3. **Create test cases** to verify the fix
   - Write `/app/test_security.py` with at least 3 test cases
   - Include tests for valid inputs, injection attempts, and edge cases
   - Test both successful operations and blocked attacks

## Application Details

The vulnerable application accepts a hostname/IP via HTTP POST and executes a ping command. The current implementation:
- Uses `subprocess.run()` with `shell=True`
- Directly concatenates user input into command strings
- Has no input validation
- Returns raw command output to users

## Security Requirements

1. **Input Validation**: Only allow alphanumeric characters, dots, and hyphens in hostnames
2. **Safe Execution**: Use `subprocess.run()` with argument lists (no shell=True)
3. **Output Sanitization**: Remove any shell metacharacters from output
4. **Error Handling**: Return generic error messages (don't leak system details)
5. **Rate Limiting**: Track requests per IP (simulate with in-memory counter)

## Expected Outputs

- `/app/security_report.txt`: Document the vulnerability with:
  - Line numbers of vulnerable code
  - Description of the security flaw
  - Example payload that exploits it
  - Potential impact

- `/app/fixed_monitor.py`: The secure implementation with:
  - Proper input validation function
  - Safe command execution
  - Sanitized output
  - HTTP server that handles POST requests

- `/app/test_security.py`: Test file that:
  - Imports and tests both vulnerable and fixed versions
  - Contains at least 3 distinct test functions
  - Verifies valid inputs work and malicious inputs are blocked
  - Runs without external dependencies (uses mocks)

## Success Criteria

The tests will verify:
1. The fixed implementation rejects command injection attempts
2. Valid hostnames (like "google.com" or "8.8.8.8") work correctly
3. No shell metacharacters are passed to subprocess
4. The security report accurately identifies the vulnerability
5. The test file properly exercises both valid and malicious cases