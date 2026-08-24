#!/bin/bash
# Legacy build script for Project Gamma
# Do not modify - this is reference only

set -e

# Configuration
PROJECT_NAME="project_gamma"
BUILD_TYPE="${1:-release}"
COMPILER="g++"
STD_VERSION="c++17"

# Source directories
SRC_DIR="src"
INCLUDE_DIR="include"
BUILD_DIR="build_${BUILD_TYPE}"

# Read config
CONFIG_FILE="config/project_config.json"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file not found"
    exit 1
fi

# Parse config
MAX_THREADS=$(jq -r '.max_threads' "$CONFIG_FILE")
ENABLE_LOGGING=$(jq -r '.enable_logging' "$CONFIG_FILE")
VERSION_MAJOR=$(jq -r '.version.major' "$CONFIG_FILE")
VERSION_MINOR=$(jq -r '.version.minor' "$CONFIG_FILE")
PROJECT_ID=$(jq -r '.project_id' "$CONFIG_FILE")

# Generate config header
mkdir -p "$INCLUDE_DIR"
cat > "${INCLUDE_DIR}/project_config.h" << EOF
// Auto-generated configuration
#ifndef PROJECT_CONFIG_H
#define PROJECT_CONFIG_H

#define MAX_THREADS ${MAX_THREADS}
#define ENABLE_LOGGING ${ENABLE_LOGGING}
#define VERSION_MAJOR ${VERSION_MAJOR}
#define VERSION_MINOR ${VERSION_MINOR}
#define PROJECT_ID "${PROJECT_ID}"

#endif // PROJECT_CONFIG_H
EOF

echo "Generated config header"

# Set compiler flags
if [ "$BUILD_TYPE" = "debug" ]; then
    CFLAGS="-g -O0 -DDEBUG -Wall -Wextra"
else
    CFLAGS="-O3 -DNDEBUG -Wall"
fi

CFLAGS="$CFLAGS -std=${STD_VERSION} -I${INCLUDE_DIR}"

# Create build directory
mkdir -p "$BUILD_DIR"

# Compile
echo "Building ${PROJECT_NAME} (${BUILD_TYPE})..."
$COMPILER $CFLAGS -o "${BUILD_DIR}/${PROJECT_NAME}" "${SRC_DIR}/main.cpp"

echo "Build complete: ${BUILD_DIR}/${PROJECT_NAME}"