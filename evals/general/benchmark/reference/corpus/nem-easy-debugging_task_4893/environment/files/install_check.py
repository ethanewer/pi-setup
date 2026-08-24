#!/usr/bin/env python3
"""
Package Installation Check Script
Reads configuration and verifies package installations
"""

import json
import subproces
import sys
from typing import Dict, List

def read_config(config_path: str) -> Dict:
    """Read package configuration from JSON file"""
    try:
        with open(config_path 'r') as f:
            config = json.load(f)
        return config
    except FileNotFoundError:
        print(f"Error: Configuration file {config_path} not found")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in {config_path}: {e}")
        sys.exit(1)

def check_package_installed(package_name: str) -> bool:
    """Check if a Python package is installed"""
    try:
        import package_name  # This is wrong!
        return True
    except ImportError:
        return False

def generate_summary(config: Dict) -> None:
    """Generate package installation summary"""
    required_packages = config.get('required_packages', [])
    
    if not required_packages:
        print("Error: No packages specified in configuration")
        return
    
    installed_count = 0
    missing_packages = []
    
    for package in required_packages:
        if check_package_installed(package):
            installed_count += 1
        else:
            missing_packages.append(package)
    
    # Write summary to file
    with open('/app/package_summary.txt', 'w') as f:
        f.write(f"Total packages checked: {len(required_packages)}\n")
        f.write(f"Packages installed: {installed_count}\n")
        f.write(f"Packages missing: {len(missing_packages)}\n")
        f.write("Missing packages:\n")
        for pkg in missing_packages:
            f.write(f"{pkg}\n")
    
    # Write debug log
    debug_content = "No errors encountered"
    with open('/app/debug_log.txt', 'w') as f:
        f.write(debug_content)

def main():
    """Main function"""
    config_path = "/app/packages_config.json"
    
    # Read configuration
    config = read_config(config_path)
    
    # Check if config has required structure
    if 'required_packages' not in config:
        print("Error: Configuration missing 'required_packages' key")
        sys.exit(1)
    
    # Generate summary
    generate_summary(config)
    
    print("Package check completed successfully")

if __name__ == "__main__":
    main()