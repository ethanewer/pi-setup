You are given a broken CMake configuration file for a simple C project. Your task is to analyze the file, identify the errors, and create a corrected version that will successfully build the project.

## Project Structure
The project has the following files (you do not need to create these, but the CMakeLists.txt must reference them correctly):
- `src/main.c` - Main program file
- `src/utils.c` - Utility functions implementation
- `include/utils.h` - Header file for utilities

## Requirements for Correct CMakeLists.txt
The fixed CMakeLists.txt must meet these specifications:
1. **Project name**: Must be "SimpleProject"
2. **Source files**: Must include both `src/main.c` and `src/utils.c`
3. **Include directory**: Must add the `include` directory to the compiler's include path
4. **Executable name**: Must create an executable named "simple_app"
5. **C standard**: Must require C11 standard

## Provided Broken File
The broken CMakeLists.txt is located at `/app/CMakeLists.txt`. It contains several errors that violate the requirements above.

## Your Task
1. Read and analyze `/app/CMakeLists.txt` to identify all errors
2. Create a corrected version that meets all requirements
3. Save the corrected file to `/app/fixed/CMakeLists.txt`

## Expected Outputs
- `/app/fixed/CMakeLists.txt`: The corrected CMake configuration file

## Test Verification
The tests will verify your solution by:
1. Checking that `/app/fixed/CMakeLists.txt` exists
2. Validating the file content contains:
   - Correct project name: `project(SimpleProject)`
   - Both source files referenced: `src/main.c` and `src/utils.c`
   - Correct executable name: `add_executable(simple_app ...)`
   - Include directory specification: `include` directory added
   - C11 standard setting: Either `set(CMAKE_C_STANDARD 11)` or equivalent

## Notes
- You may assume CMake version 3.10 or higher
- The CMakeLists.txt should be at the project root (same level as `src/` and `include/` directories)
- Your solution must produce a valid CMakeLists.txt that would successfully build the project