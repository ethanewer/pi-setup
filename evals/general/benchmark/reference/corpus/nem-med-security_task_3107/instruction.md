# Security Vulnerability Analysis and Fix Challenge

You are a security engineer tasked with analyzing and fixing vulnerabilities in a simple web authentication system. The system has multiple security flaws that need to be identified, documented, and corrected.

## Background

A developer has created a Python-based web authentication system that handles user login and session management. The system is currently deployed in a test environment at `http://localhost:8080`. However, security testing has revealed several vulnerabilities.

## Your Task

1. **Analyze the Vulnerable System**
   - Examine the provided vulnerable application at `/app/vulnerable_auth.py`
   - Run the application to understand its behavior (use `python3 /app/vulnerable_auth.py` in background)
   - Test the system for security vulnerabilities using the provided test client at `/app/test_client.py`
   - Identify ALL security vulnerabilities in the system

2. **Create Security Analysis Report**
   - Create a detailed security report at `/app/security_report.json`
   - The report must be valid JSON with the following structure:
     ```json
     {
       "vulnerabilities": [
         {
           "type": "vulnerability_type",
           "location": "file:line_number or function_name",
           "description": "brief_description",
           "severity": "low|medium|high|critical",
           "exploit_scenario": "how_could_this_be_exploited"
         }
       ],
       "summary": {
         "total_vulnerabilities": integer,
         "critical_count": integer,
         "high_count": integer
       }
     }
     ```
   - You must identify at least 3 distinct vulnerabilities
   - Include at least one vulnerability with "critical" severity

3. **Fix the Vulnerabilities**
   - Create a fixed version of the application at `/app/fixed_auth.py`
   - The fixed application must maintain all original functionality
   - You must fix ALL identified vulnerabilities
   - Add appropriate security measures while preserving the API
   - Include input validation, output encoding, and proper session handling

4. **Verify Your Fixes**
   - Test that your fixed application works correctly with the provided test client
   - Ensure that exploit attempts against the original vulnerabilities fail in the fixed version

## Expected Outputs

- `/app/security_report.json`: JSON security analysis report with vulnerability details
- `/app/fixed_auth.py`: Corrected Python application with all vulnerabilities fixed

## Security Requirements

Your fixed application must:
- Prevent SQL injection attacks
- Implement proper password hashing with salt
- Use secure session tokens
- Validate and sanitize all user inputs
- Handle errors without leaking sensitive information
- Implement rate limiting for login attempts
- Use secure defaults for all security settings

## Testing Instructions

1. Start the vulnerable application: `python3 /app/vulnerable_auth.py &`
2. Test vulnerabilities: `python3 /app/test_client.py --test-vulnerabilities`
3. Start your fixed application: `python3 /app/fixed_auth.py &`
4. Verify fixes: `python3 /app/test_client.py --test-fixes`

**Note**: The test system will verify:
- Your security report contains accurate vulnerability information
- The fixed application correctly blocks all identified attacks
- The application maintains functional login/logout capabilities
- No new vulnerabilities are introduced by your fixes