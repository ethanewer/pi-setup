## Legacy Build System Migration and Configuration Generation

You are tasked with migrating a legacy C++ project from a custom build script to a modern CMake build system while preserving specific build-time configurations.

The legacy project has the following structure:
```
/app/
├── legacy_build.sh        # Custom build script
├── config_template.h.in   # Template for generated header
├── src/
│   └── main.cpp          # Main source file
└── config/
    └── project_config.json  # Build configuration
```

**Your Task:**

1. **Analyze the Legacy Build System**
   - Read `/app/legacy_build.sh` to understand the build process
   - Extract the compiler flags, defines, and include paths
   - Identify the configuration parameters that need to be preserved

2. **Generate CMakeLists.txt**
   - Create a modern CMakeLists.txt in `/app/` that replicates the build process
   - Must support both Debug and Release configurations
   - Must handle the configuration header generation
   - Must set appropriate compiler flags for C++17

3. **Create Configuration Header Generator**
   - Write a Python script at `/app/generate_config.py` that:
     - Reads `/app/config/project_config.json`
     - Processes `/app/config_template.h.in`
     - Generates `/app/include/project_config.h` with proper #define statements
   - The script must validate that all required fields exist in the JSON

4. **Integrate with CMake**
   - Configure CMake to run the Python script before building
   - Ensure the generated header is available during compilation
   - Set up proper dependencies so the header regenerates when config changes

5. **Create Build Verification Script**
   - Write a bash script at `/app/verify_build.sh` that:
     - Runs the CMake build for both Debug and Release
     - Verifies the generated header exists and contains expected defines
     - Runs the built executable and checks exit code
     - Outputs a summary to `/app/build_summary.json`

**Expected Outputs:**
- `/app/CMakeLists.txt` - Complete CMake configuration
- `/app/generate_config.py` - Python script for header generation
- `/app/verify_build.sh` - Build verification script
- `/app/include/project_config.h` - Generated configuration header
- `/app/build_summary.json` - Build verification results

**Success Criteria:**
1. The CMake build must produce identical binaries to the legacy script (same compiler flags, defines)
2. The generated header must correctly transform all JSON fields to C++ #define statements
3. The verification script must pass for both Debug and Release configurations
4. All output files must be in the specified locations with correct formats