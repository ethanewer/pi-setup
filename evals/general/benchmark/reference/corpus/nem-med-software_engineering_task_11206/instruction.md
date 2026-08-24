## Build System Feature Flag Manager

You are tasked with implementing a Python-based build system feature flag manager that handles conditional compilation and dependency resolution. This system processes a project configuration and generates appropriate build commands based on enabled features.

## Project Overview

A C++ project uses feature flags to conditionally include different components. The build system must:
1. Parse project configuration files
2. Resolve feature dependencies and conflicts
3. Generate compilation commands with correct include paths and defines
4. Handle cross-platform compatibility (Linux/macOS)

## Your Task

### 1. Parse Configuration Files
Read two configuration files from `/app/config`:
- `project.yaml`: Main project configuration with feature definitions
- `dependencies.json`: Dependency graph and platform-specific settings

### 2. Feature Resolution
Implement feature flag resolution with these rules:
- Some features require other features (dependencies)
- Some features are mutually exclusive (conflicts)
- Features can have platform-specific implementations
- Default features should be enabled unless explicitly disabled

### 3. Generate Build Commands
Based on the resolved features, generate:
- Compilation commands for each source file
- Include paths based on active features
- Preprocessor defines (`-D` flags)
- Linker flags for required libraries

### 4. Output Results
Create two output files in `/app/output`:
1. `build_commands.json`: Structured build commands
2. `feature_summary.txt`: Human-readable feature summary

## Configuration Files

### project.yaml
```yaml
project: math_library
default_features: [core, logging]
features:
  core:
    description: "Basic math operations"
    source_files: ["src/core/*.cpp"]
    defines: [MATH_CORE]
    
  logging:
    description: "Debug logging support"
    source_files: ["src/logging/*.cpp"]
    defines: [ENABLE_LOGGING]
    dependencies: [core]
    
  advanced:
    description: "Advanced math functions"
    source_files: ["src/advanced/*.cpp"]
    defines: [MATH_ADVANCED]
    dependencies: [core]
    conflicts: [legacy]
    
  legacy:
    description: "Legacy compatibility"
    source_files: ["src/legacy/*.cpp"]
    defines: [LEGACY_MODE]
    conflicts: [advanced]
    
  gpu:
    description: "GPU acceleration"
    source_files: ["src/gpu/*.cpp"]
    defines: [USE_GPU]
    dependencies: [core]
    platform_specific: true
```

### dependencies.json
```json
{
  "platforms": {
    "linux": {
      "compiler": "g++",
      "std": "c++17",
      "lib_dirs": ["/usr/local/lib"],
      "include_dirs": ["/usr/local/include"]
    },
    "macos": {
      "compiler": "clang++",
      "std": "c++17",
      "lib_dirs": ["/opt/homebrew/lib"],
      "include_dirs": ["/opt/homebrew/include"]
    }
  },
  "external_libs": {
    "gpu": {
      "linux": ["-lOpenCL"],
      "macos": ["-framework OpenCL"]
    }
  }
}
```

## Input Format

Your program will receive command-line arguments specifying enabled features:
```bash
python build_manager.py --enable advanced,gpu --disable logging
```

Additionally, detect the current platform (Linux or macOS) automatically.

## Expected Outputs

### 1. `/app/output/build_commands.json`
```json
{
  "platform": "linux",
  "compiler": "g++",
  "cpp_standard": "c++17",
  "active_features": ["core", "advanced", "gpu"],
  "source_files": [
    "src/core/add.cpp",
    "src/core/subtract.cpp",
    "src/advanced/trigonometry.cpp"
  ],
  "include_dirs": [
    "include",
    "/usr/local/include"
  ],
  "defines": [
    "MATH_CORE",
    "MATH_ADVANCED",
    "USE_GPU"
  ],
  "lib_dirs": [
    "/usr/local/lib"
  ],
  "linker_flags": [
    "-lOpenCL"
  ],
  "compilation_commands": [
    {
      "file": "src/core/add.cpp",
      "command": "g++ -std=c++17 -Iinclude -I/usr/local/include -DMATH_CORE -DMATH_ADVANCED -DUSE_GPU -c src/core/add.cpp -o build/core/add.o"
    }
  ]
}
```

### 2. `/app/output/feature_summary.txt`
```
Build Configuration Summary
===========================
Platform: linux
Compiler: g++ (c++17)

Active Features (3):
  • core - Basic math operations
  • advanced - Advanced math functions
  • gpu - GPU acceleration (platform-specific)

Excluded Features (2):
  • logging - Disabled by user
  • legacy - Conflicts with 'advanced'

Dependency Resolution:
  ✓ core: Enabled (default)
  ✓ advanced: Enabled, requires core
  ✗ logging: Disabled
  ✗ legacy: Disabled (conflicts with advanced)
  ✓ gpu: Enabled, requires core

Build Commands Generated: 5
Output Directory: build/
```

## Implementation Requirements

1. **Error Handling**:
   - Detect and report feature conflicts
   - Validate all dependencies exist
   - Check for circular dependencies
   - Handle missing source files gracefully

2. **Platform Detection**:
   - Auto-detect Linux vs macOS
   - Use appropriate compiler and flags
   - Handle platform-specific features

3. **File Structure**:
   - Assume source files exist at specified paths
   - Create output directory if needed
   - Generate compilation commands for each source file

4. **Validation Rules**:
   - Features must exist in configuration
   - Dependencies must be satisfiable
   - Conflicts must prevent co-activation
   - Platform-specific features must be valid for current platform

## Testing Criteria

The tests will verify:
1. Correct resolution of feature dependencies and conflicts
2. Proper platform detection and flag selection
3. Accurate generation of compilation commands
4. Complete output files with expected structure
5. Handling of edge cases (conflicts, missing dependencies)

Your solution must work with the provided configuration files and produce the exact output formats specified.