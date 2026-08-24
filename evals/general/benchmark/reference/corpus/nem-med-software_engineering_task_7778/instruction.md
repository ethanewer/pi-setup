# Build System Configuration and Data Processing Pipeline

You are tasked with configuring a build system for a data processing pipeline that combines multiple file formats. The system must:
1. Read configuration from multiple sources
2. Generate build artifacts in the correct format
3. Process data through a transformation pipeline
4. Validate outputs against expected schemas

## Context
A research team has a data processing system with the following components:
- Input CSV files with sensor readings
- Configuration in JSON format defining transformations  
- A Python script that performs data aggregation
- A build system to orchestrate everything

The system currently has issues with:
- Incorrect file paths in build configuration
- Missing dependency declarations
- Improper output format validation

## Your Task

### 1. Fix the Build Configuration
Examine `/app/build.yaml` which contains the build system configuration. Fix the following issues:
- Correct all relative file paths to use absolute paths from `/app/`
- Ensure all dependencies are properly declared
- Fix the execution order so steps run in correct sequence
- Add missing environment variable declarations

### 2. Implement Data Processing Script
Create `/app/process_data.py` that:
- Reads input CSV from `/app/input/sensor_data.csv`
- Applies transformations specified in `/app/config/transformations.json`
- Validates data according to `/app/config/schema.json`
- Outputs results to `/app/output/aggregated_data.json`
- Logs errors to `/app/output/process.log`

The script must handle:
- Missing or malformed input data
- Type conversion errors (e.g., string to float)
- Schema validation failures
- File permission issues

### 3. Create Validation Report
Generate `/app/output/validation_report.md` containing:
- Summary statistics (row count, column count, error count)
- Schema compliance percentage
- List of validation errors with line numbers
- Processing time metrics

### 4. Create Makefile for Automation
Create `/app/Makefile` with targets:
- `make build`: Runs the entire pipeline
- `make test`: Validates outputs against expected results
- `make clean`: Removes all generated files
- `make validate`: Runs only validation steps

## Expected Outputs
- `/app/process_data.py`: Python script implementing data processing
- `/app/Makefile`: Build automation file with specified targets
- `/app/output/aggregated_data.json`: Processed data in JSON format
- `/app/output/validation_report.md`: Validation summary in Markdown
- `/app/output/process.log`: Error and debug log file

## Success Criteria
1. The pipeline must process at least 95% of input rows successfully
2. All output files must be created with correct permissions
3. The Makefile targets must work correctly when called
4. Validation report must include all required metrics
5. No hardcoded paths - use configuration from `/app/build.yaml`